module repository

import models
import time

// ==================== JOBS (Pilier 4 — file asynchrone) ====================

// create_job insère un job en attente (pending) et retourne son identifiant.
pub fn (mut r Repository) create_job(job models.Job) !int {
	job_id := sql r.db {
		insert job into models.Job
	}!
	return job_id
}

// get_job retourne un job d'une organisation (scoping tenant).
// PAS de `limit 1` : l'ORM V 0.5.2 corrompt la liaison des paramètres des conditions
// quand un LIMIT (même littéral) est présent avec >= 2 conditions WHERE (bug observé :
// la 2e condition recevait la valeur du LIMIT). Tranche mémoire : id unique par tenant.
pub fn (r &Repository) get_job(job_id int, org_id int) ?models.Job {
	result := sql r.db {
		select from models.Job where id == job_id && organization_id == org_id
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// get_jobs retourne la page de jobs d'une organisation, du plus récent au plus ancien.
// Le LIMIT/OFFSET est appliqué en mémoire (V 0.5.2 ne paramètre pas LIMIT/OFFSET en ORM).
pub fn (r &Repository) get_jobs(org_id int, page int, page_size int) ([]models.Job, int) {
	jobs := sql r.db {
		select from models.Job where organization_id == org_id order by id desc
	} or { []models.Job{} }
	total := jobs.len
	start := if page > 1 { (page - 1) * page_size } else { 0 }
	mut end := start + page_size
	if end > jobs.len {
		end = jobs.len
	}
	if start >= jobs.len {
		return []models.Job{}, total
	}
	return jobs[start..end], total
}

// get_pending_jobs retourne les jobs pending/running d'une organisation.
// Utilisé aux endpoints de surveillance (statut courant).
pub fn (r &Repository) get_active_jobs(org_id int) []models.Job {
	return sql r.db {
		select from models.Job where organization_id == org_id && (status == models.job_pending || status == models.job_running) order by id desc
	} or { [] }
}

// update_job_running passe un job en running (démarrage du traitement).
pub fn (r &Repository) update_job_running(job_id int, org_id int) ! {
	r.db.exec_param_many("UPDATE job SET status = \$1, started_at = \$2, error_ = '' WHERE id = \$3 AND organization_id = \$4;", [
		models.job_running,
		time.now().format(),
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// update_job_progress met à jour la progression (0-100) d'un job en cours.
pub fn (r &Repository) update_job_progress(job_id int, org_id int, progress int) ! {
	r.db.exec_param_many('UPDATE job SET progress = \$1 WHERE id = \$2 AND organization_id = \$3;', [
		'${progress}',
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// finish_job_done marque un job terminé avec succès (progress 100).
pub fn (r &Repository) finish_job_done(job_id int, org_id int, result string) ! {
	r.db.exec_param_many('UPDATE job SET status = \$1, progress = 100, result = \$2, finished_at = \$3 WHERE id = \$4 AND organization_id = \$5;', [
		models.job_done,
		result,
		time.now().format(),
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// schedule_retry programme le retry d'un job (statut pending, attempts+1, backoff).
pub fn (r &Repository) schedule_retry(job_id int, org_id int, attempts int, max_attempts int, next_retry_at time.Time) ! {
	r.db.exec_param_many('UPDATE job SET status = \$1, attempts = \$2, next_retry_at = \$3 WHERE id = \$4 AND organization_id = \$5;', [
		models.job_pending,
		'${attempts}',
		next_retry_at.format(),
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// fail_job marque un job en échec définitif (dead-letter) avec le message d'erreur,
// en archivant le nombre réel de tentatives effectuées.
pub fn (r &Repository) fail_job(job_id int, org_id int, error_message string, attempts int) ! {
	r.db.exec_param_many('UPDATE job SET status = \$1, error_ = \$2, attempts = \$3, finished_at = \$4 WHERE id = \$5 AND organization_id = \$6;', [
		models.job_failed,
		error_message,
		'${attempts}',
		time.now().format(),
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// get_pending_jobs_for_recovery retourne les jobs en attente (pending) les plus anciens,
// pour les remettre en file au démarrage du process.
pub fn (r &Repository) get_pending_jobs_for_recovery() []models.Job {
	return sql r.db {
		select from models.Job where status == models.job_pending order by id asc limit 50
	} or { [] }
}

// retry_job replace un job en échec en pending (file de retry), remet à zéro les
// tentatives (budget complet) et vide l'erreur.
pub fn (r &Repository) retry_job(job_id int, org_id int) ! {
	r.db.exec_param_many("UPDATE job SET status = \$1, attempts = 0, progress = 0, error_ = '', next_retry_at = NULL, finished_at = NULL WHERE id = \$2 AND organization_id = \$3;", [
		models.job_pending,
		'${job_id}',
		'${org_id}',
	]) or { return err }
}

// reset_stale_running remet en pending les jobs laissés 'running' par un arrêt
// brutal du process (récupération au démarrage). Retourne le nombre de jobs repris.
pub fn (mut r Repository) reset_stale_running() int {
	n := sql r.db {
		select count from models.Job where status == 'running'
	} or { 0 }
	sql r.db {
		update models.Job set status = 'pending' where status == 'running'
	} or {}
	return n
}

// purge_finished_jobs supprime les jobs terminés (done/failed) plus anciens que `before`.
// Retourne le nombre de lignes purgées.
pub fn (mut r Repository) purge_finished_jobs(org_id int, before time.Time) int {
	n := sql r.db {
		select count from models.Job where organization_id == org_id && status in ['done', 'failed'] && created_at < before
	} or { 0 }
	sql r.db {
		delete from models.Job where organization_id == org_id && status in ['done', 'failed'] && created_at < before
	} or {}
	return n
}
