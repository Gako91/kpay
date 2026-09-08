module api

import veb
import dto
import models
import time
import json2
import encoding.base64

// CreateLeaveRequestInput définit le body pour soumettre une demande de congé (RH / admin)
pub struct CreateLeaveRequestInput {
pub:
	employee_id int
	leave_type  string
	start_date  string // YYYY-MM-DD
	end_date    string // YYYY-MM-DD
	days_count  f32
	reason      string
}

// UpdateLeaveStatusInput définit le body pour approuver/refuser un congé (compatibilité)
pub struct UpdateLeaveStatusInput {
pub:
	status string // 'approuve' | 'refuse'
}

// resolve_actor_employee retourne le dossier employé lié au compte authentifié (si lié).
fn (app &App) resolve_actor_employee(ctx Context) ?models.Employee {
	user := app.repo.get_user_by_username(ctx.user_sub) or { return none }
	return app.repo.get_employee_by_user_id(user.id, ctx.user_org)
}

// resolver_de_la_demande — permissions applicables à une demande pour l'acteur courant.
fn (app &App) can_decide_mgr(ctx Context, lr models.LeaveRequest) bool {
	if ctx.has_role(['admin', 'payroll_officer']) {
		return true
	}
	actor := app.resolve_actor_employee(ctx) or { return false }
	requester := app.repo.get_employee_by_id(lr.employee_id, ctx.user_org) or { return false }
	return (requester.manager_id or { 0 }) == actor.id
}

// can_touch_leave — l'acteur peut-il voir/joindre un justificatif (propriétaire, N+1 ou RH) ?
fn (app &App) can_touch_leave(ctx Context, lr models.LeaveRequest) bool {
	if ctx.has_role(['admin', 'payroll_officer']) {
		return true
	}
	actor := app.resolve_actor_employee(ctx) or { return false }
	if actor.id == lr.employee_id {
		return true
	}
	requester := app.repo.get_employee_by_id(lr.employee_id, ctx.user_org) or { return false }
	return (requester.manager_id or { 0 }) == actor.id
}

// create_leave POST /leaves - Soumettre une demande de congé (RH / admin, au nom d'un employé)
@['/leaves'; post]
pub fn (mut app App) create_leave(mut ctx Context) veb.Result {
	body := ctx.req.data
	input := json2.decode[CreateLeaveRequestInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	start := time.parse_iso8601(input.start_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format start_date invalide (YYYY-MM-DD attendu)'))
	}
	end := time.parse_iso8601(input.end_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format end_date invalide (YYYY-MM-DD attendu)'))
	}

	emp := app.repo.get_employee_by_id(input.employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé introuvable'))
	}

	created := app.leave_svc.submit_request(emp, input.leave_type, start, end, input.days_count, input.reason, ctx.user_org) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'CREATE', 'leave_request', created.id, 'Demande de congé créée pour employé ${created.employee_id}')

	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{
		success: true
		data: '${created.id}'
		message: 'Demande de congé soumise avec succès'
	})
}

// get_leaves GET /leaves - Lister les demandes de congé
// (toutes : Admin/RH ; mon équipe : &my_team=1 ; par employé : &employee_id=)
@['/leaves']
pub fn (app &App) get_leaves(mut ctx Context) veb.Result {
	if ctx.query['my_team'] == '1' {
		actor := app.resolve_actor_employee(ctx) or {
			ctx.res.set_status(.forbidden)
			return ctx.json(dto.error_response('Aucun dossier employé lié à ce compte — réservé aux managers'))
		}
		requests := app.repo.get_leave_requests_for_manager(actor.id, ctx.user_org) or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
		}
		return ctx.json(requests)
	}

	emp_id_str := ctx.query['employee_id']
	if emp_id_str.len > 0 {
		emp_id := emp_id_str.int()
		requests := app.repo.get_leave_requests_by_employee(emp_id, ctx.user_org) or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
		}
		return ctx.json(requests)
	}

	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}

	requests := app.repo.get_all_leave_requests(ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
	}

	return ctx.json(requests)
}

// update_leave_status PUT /leaves/:id/status - Décision RH directe (compatibilité)
@['/leaves/:id/status'; put]
pub fn (mut app App) update_leave_status(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}

	body := ctx.req.data
	input := json2.decode[UpdateLeaveStatusInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	if input.status != 'approuve' && input.status != 'refuse' {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Statut invalide. Valeurs autorisees: 'approuve', 'refuse'"))
	}

	// La décision RH peut concerner une demande en attente N+1 ou en attente RH
	// (le service débite le solde et notifie).
	if input.status == 'refuse' {
		app.leave_svc.rh_reject(id, ctx.user_org, ctx.user_sub, 'Décision RH directe') or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur mise à jour statut conge: ${err}'))
		}
	} else {
		app.leave_svc.rh_approve(id, ctx.user_org, ctx.user_sub) or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur mise à jour statut conge: ${err}'))
		}
	}

	app.audit_action(mut ctx, 'UPDATE_STATUS', 'leave_request', id, 'Demande de congé passe à ${input.status}')

	return ctx.json(dto.ApiResponse{
		success: true
		data: '${id}'
		message: 'Statut mis à jour avec succès'
	})
}

// ==================== ESS : MES DEMANDES & SOLDES ====================

// create_my_leave POST /me/leaves - L'employé connecté soumet sa propre demande
@['/me/leaves'; post]
pub fn (mut app App) create_my_leave(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}

	body := ctx.req.data
	input := json2.decode[dto.CreateMyLeaveInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	start := time.parse_iso8601(input.start_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format start_date invalide (YYYY-MM-DD attendu)'))
	}
	end := time.parse_iso8601(input.end_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format end_date invalide (YYYY-MM-DD attendu)'))
	}

	created := app.leave_svc.submit_request(emp, input.leave_type, start, end, input.days_count, input.reason, ctx.user_org) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'leave.create.self', 'leave_request', created.id, 'Demande ${created.leave_type} soumise (ESS)')
	ctx.res.set_status(.created)
	return ctx.json(created)
}

// get_my_leaves GET /me/leaves - Liste des demandes de l'employé connecté
@['/me/leaves']
pub fn (app &App) get_my_leaves(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	requests := app.repo.get_leave_requests_by_employee(emp.id, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
	}
	return ctx.json(requests)
}

// get_my_leave_balance GET /me/leave-balance?year= - Soldes annuels de l'employé connecté
@['/me/leave-balance']
pub fn (mut app App) get_my_leave_balance(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	year := if ctx.query['year'].len > 0 {
		ctx.query['year'].int()
	} else {
		time.now().year
	}
	balances := app.leave_svc.get_balance(emp, year, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur chargement des soldes de conge: ${err}'))
	}
	return ctx.json(balances)
}

// ==================== WORKFLOW 2 NIVEAUX ====================

// mgr_approve_leave POST /leaves/:id/mgr-approve - Validation N+1
@['/leaves/:id/mgr-approve'; post]
pub fn (mut app App) mgr_approve_leave(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	lr := app.repo.get_leave_request(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Demande de congé introuvable'))
	}
	if !app.can_decide_mgr(ctx, lr) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — réservé au manager du demandeur ou au RH'))
	}

	updated := app.leave_svc.mgr_approve(id, ctx.user_org, ctx.user_sub) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'leave.mgr_approve', 'leave_request', id, 'Demande validée au niveau N+1 par ${ctx.user_sub}')
	return ctx.json(updated)
}

// mgr_reject_leave POST /leaves/:id/mgr-reject - Refus N+1 (motif obligatoire)
@['/leaves/:id/mgr-reject'; post]
pub fn (mut app App) mgr_reject_leave(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	lr := app.repo.get_leave_request(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Demande de congé introuvable'))
	}
	if !app.can_decide_mgr(ctx, lr) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — réservé au manager du demandeur ou au RH'))
	}

	body := ctx.req.data
	input := json2.decode[dto.LeaveRejectInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	updated := app.leave_svc.mgr_reject(id, ctx.user_org, ctx.user_sub, input.reason) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'leave.mgr_reject', 'leave_request', id, 'Demande refusée au niveau N+1 par ${ctx.user_sub}')
	return ctx.json(updated)
}

// rh_approve_leave POST /leaves/:id/rh-approve - Validation RH (finale, débite le solde)
@['/leaves/:id/rh-approve'; post]
pub fn (mut app App) rh_approve_leave(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	updated := app.leave_svc.rh_approve(id, ctx.user_org, ctx.user_sub) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'leave.rh_approve', 'leave_request', id, 'Demande approuvée par la RH (${ctx.user_sub})')
	return ctx.json(updated)
}

// rh_reject_leave POST /leaves/:id/rh-reject - Refus RH (motif obligatoire)
@['/leaves/:id/rh-reject'; post]
pub fn (mut app App) rh_reject_leave(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	body := ctx.req.data
	input := json2.decode[dto.LeaveRejectInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	updated := app.leave_svc.rh_reject(id, ctx.user_org, ctx.user_sub, input.reason) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'leave.rh_reject', 'leave_request', id, 'Demande refusée par la RH (${ctx.user_sub})')
	return ctx.json(updated)
}

// ==================== JUSTIFICATIF (CONGÉ MALADIE) ====================

// upload_leave_justificatif POST /leaves/:id/justificatif - Enregistre un PDF justificatif
@['/leaves/:id/justificatif'; post]
pub fn (mut app App) upload_leave_justificatif(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	lr := app.repo.get_leave_request(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Demande de congé introuvable'))
	}
	if lr.leave_type != 'maladie' {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Le justificatif est réservé aux demandes de type maladie'))
	}
	if !app.can_touch_leave(ctx, lr) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — seul le demandeur, son N+1 ou le RH peut joindre un justificatif'))
	}

	body := ctx.req.data
	input := json2.decode[dto.JustificatifInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	raw := base64.decode(input.content)
	if raw.len == 0 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Fichier vide'))
	}
	if raw.len > 1_048_576 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Fichier trop volumineux (maximum 1 Mo)'))
	}
	is_pdf := raw.len >= 4 && raw[0..4] == '%PDF'.bytes()
	if !is_pdf {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Le justificatif doit être un fichier PDF'))
	}

	object_name := 'org_${ctx.user_org}/justificatif_${id}.pdf'
	app.storage_svc.upload_file(object_name, raw) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur enregistrement du justificatif: ${err}'))
	}
	app.repo.set_leave_justificatif(id, ctx.user_org, object_name) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur mise à jour de la demande: ${err}'))
	}

	app.audit_action(mut ctx, 'leave.justificatif', 'leave_request', id, 'Justificatif déposé pour la demande ${id}')
	return ctx.json(dto.ApiResponse{
		success: true
		data: object_name
		message: 'Justificatif enregistré avec succès'
	})
}

// get_leave_justificatif GET /leaves/:id/justificatif - Téléchargement du justificatif
@['/leaves/:id/justificatif']
pub fn (mut app App) get_leave_justificatif(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'leave_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	lr := app.repo.get_leave_request(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Demande de congé introuvable'))
	}
	if !app.can_touch_leave(ctx, lr) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé'))
	}
	if lr.justificatif_path.len == 0 {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun justificatif déposé pour cette demande'))
	}

	data := app.storage_svc.download_file(lr.justificatif_path) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Justificatif introuvable sur le stockage'))
	}

	app.audit_action(mut ctx, 'leave.justificatif.download', 'leave_request', id, 'Justificatif téléchargé (demande ${id})')
	ctx.res.header.set(.content_type, 'application/pdf')
	ctx.res.header.set_custom('Content-Disposition', 'inline; filename="justificatif_${id}.pdf"') or {}
	return ctx.send_response_to_client('application/pdf', data.bytestr())
}