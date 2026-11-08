module api

import veb
import time
import json2
import models
import dto
import repository
import veb.sse

// ==================== JOBS (Pilier 4 — file asynchrone, SSE) ====================

// get_job GET /jobs/:id — État courant d'un job (statut, progression, erreur).
@['/jobs/:id']
pub fn (app &App) get_job(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'job_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	job := app.repo.get_job(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Job non trouvé'))
	}
	return ctx.json(job)
}

// list_jobs GET /jobs — Historique paginé des jobs de l'organisation.
@['/jobs']
pub fn (app &App) list_jobs(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	page := if ctx.query['page'].len > 0 { ctx.query['page'].int() } else { 1 }
	if page < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'page' doit être >= 1"))
	}
	page_size := if ctx.query['limit'].len > 0 { ctx.query['limit'].int() } else { 25 }
	if page_size < 1 || page_size > 100 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'limit' doit être entre 1 et 100"))
	}

	jobs, total := app.repo.get_jobs(ctx.user_org, page, page_size)
	resp := dto.PageResponse[models.Job]{
		data: jobs
		page: page
		page_size: page_size
		total: total
		total_pages: if page_size > 0 { (total + page_size - 1) / page_size } else { 0 }
	}
	return ctx.json(resp)
}

// retry_job_handler POST /jobs/:id/retry — Replace un job en échec (dead-letter) en file.
@['/jobs/:id/retry'; post]
pub fn (mut app App) retry_job_handler(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'job_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	job := app.repo.get_job(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Job non trouvé'))
	}
	if job.status != models.job_failed {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Seul un job en échec peut être relancé (statut actuel: '${job.status}')"))
	}
	app.jobs_svc.retry_job(mut app.repo, id, ctx.user_org, job.job_type) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors de la relance: ${err}'))
	}
	app.audit_action(mut ctx, 'job.retry', 'job', id, 'Relance du job #${id}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Job relancé' })
}

// purge_finished POST /jobs/purge — Purge les jobs terminés (done/failed) plus vieux que N jours.
@['/jobs/purge'; post]
pub fn (app &App) purge_finished(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	days := if ctx.query['days'].len > 0 { ctx.query['days'].int() } else { 30 }
	if days < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'days' doit être >= 1"))
	}
	before := time.now().add_seconds(int(-i64(days) * 86400))
	n := app.repo.purge_finished_jobs(ctx.user_org, before)
	app.audit_action(mut ctx, 'job.purge', 'job', 0, 'Purge des jobs terminés (${n})')
	return ctx.json(dto.ApiResponse{ success: true, data: '${n}', message: 'Pure effectuée (${n} jobs supprimés)' })
}

// job_events GET /events/jobs/:id — Flux SSE temps réel de progression du job.
// Authentifié par token JWT en query param (EventSource ne gère pas les headers).
@['/events/jobs/:id']
pub fn (mut app App) job_events(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'job_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	// Vérification d'existence AVANT le takeover (les erreurs JSON ne sont plus possibles ensuite)
	app.repo.get_job(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Job non trouvé'))
	}

	// Repository dédié au flux : la goroutine SSE ne doit jamais partager la
	// connexion pg de l'app (accès concurrent non sûr), cf. JobWorker.
	sse_repo := repository.new_repository(app.jobs_svc.config) or {
		ctx.res.set_status(.service_unavailable)
		return ctx.json(dto.error_response('Base de données indisponible'))
	}

	ctx.takeover_conn()
	spawn handle_job_sse(mut ctx, id, ctx.user_org, sse_repo)
	return veb.no_result()
}

// handle_job_sse asservit le flux des événements du job : émission périodique de
// l'état du job (progression 0-100), terminaison sur done/failed, fermeture propre.
fn handle_job_sse(mut ctx Context, job_id int, org_id int, repo_ repository.Repository) {
	mut repo := repo_
	defer {
		repo.close()
	}
	mut sse_conn := sse.start_connection(mut ctx.Context)

	for {
		job := repo.get_job(job_id, org_id) or { break }
		payload := json2.encode(job)
		sse_conn.send_message(event: 'job', data: payload) or { break }
		if job.status == models.job_done || job.status == models.job_failed || job.status == models.job_cancelled {
			sse_conn.send_message(event: 'done', data: job.status) or {}
			break
		}
		time.sleep(700 * time.millisecond)
	}
	sse_conn.close()
}