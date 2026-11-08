module services

import time
import json2
import common
import dto
import models
import repository

// JobTask est l'élément transporté dans la file mémoire du worker.
pub struct JobTask {
pub:
	job_id   int
	org_id   int
	job_type string
}

// JobWorker gère la file de traitement asynchrone (Pilier 4).
// L'insertion (enqueue) est faite depuis le slot veb (goroutine requête) avec le
// repository partagé ; le worker utilise UN repository dédié par job (pool propre
// à sa goroutine) pour éviter tout accès concurrent au même pool pg.
pub struct JobWorker {
pub mut:
	queue  chan JobTask
	config common.Config
}

pub fn new_job_worker(config common.Config, queue chan JobTask) JobWorker {
	return JobWorker{
		queue: queue
		config: config
	}
}

// enqueue persiste un job en pending puis le pousse dans la file mémoire.
// Le statut pending fait office de file de secours à travers les redémarrages
// (récupération au boot via recover_pending_after_restart).
pub fn (mut w JobWorker) enqueue(mut repo repository.Repository, org_id int, job_type string, payload string, created_by string, max_attempts int) !int {
	job_id := repo.create_job(models.Job{
		organization_id: org_id
		job_type: job_type
		status: models.job_pending
		progress: 0
		payload: payload
		created_by: created_by
		max_attempts: max_attempts
		created_at: time.now()
		next_retry_at: time.now()
	})!
	queue_push(w.queue, JobTask{
		job_id: job_id
		org_id: org_id
		job_type: job_type
	})
	return job_id
}

// retry_job replace un job en échec (dead-letter) en file pour un nouvel essai.
// Le compteur de tentatives est conservé (le job passera en dead-letter si ça échoue encore).
pub fn (mut w JobWorker) retry_job(mut repo repository.Repository, job_id int, org_id int, job_type string) !int {
	repo.retry_job(job_id, org_id)!
	queue_push(w.queue, JobTask{
		job_id: job_id
		org_id: org_id
		job_type: job_type
	})
	return job_id
}

// Backoff exponentiel (secondes) par tentative de retry.
const job_retry_backoffs = [2, 10, 60, 300]

// run_job_worker est la goroutine unique de consommation de la file.
// Elle tourne pendant toute la vie du process.
pub fn run_job_worker(queue chan JobTask, config common.Config) {
	for {
		task := <-queue
		process_job_task(queue, config, task)
		time.sleep(100 * time.millisecond)
	}
}

// process_job_task dispatch une tâche vers son exécuteur dédié avec un repository frais.
fn process_job_task(queue chan JobTask, config common.Config, task JobTask) {
	mut repo := repository.new_repository(config) or {
		log_error("Jobs: impossible de créer le repository pour le job ${task.job_id}: ${err}")
		return
	}
	defer {
		repo.close()
	}

	job := repo.get_job(task.job_id, task.org_id) or {
		log_error("Jobs: job ${task.job_id} introuvable")
		return
	}

	match task.job_type {
		models.job_type_payroll_run {
			process_payroll_run(mut repo, queue, task, job, config)
		}
		else {
			repo.fail_job(task.job_id, task.org_id, "Type de job inconnu: ${task.job_type}", job.attempts + 1) or {
				log_error("Jobs: erreur dead-letter job ${task.job_id}: ${err}")
			}
			log_error("Jobs: type de job inconnu '${task.job_type}'")
		}
	}
}

// process_payroll_run exécute la génération mensuelle de la paie (bulletin + sauvegarde),
// en rapportant la progression via le statut du job.
fn process_payroll_run(mut repo repository.Repository, queue chan JobTask, task JobTask, job models.Job, config common.Config) {
	req := json2.decode[dto.PayrollRunRequest](job.payload) or {
		repo.fail_job(task.job_id, task.org_id, "Payload invalide: ${err}", job.attempts + 1) or {}
		log_error("Jobs: payload invalide pour ${task.job_id}: ${err}")
		return
	}

	repo.update_job_running(task.job_id, task.org_id) or {
		log_error("Jobs: echec demarrage job ${task.job_id}: ${err}")
	}

	mut ps := new_payroll_service(mut repo)
	ps.set_mailer(new_mailer_service(config))

	run := ps.run_and_save_monthly_payroll(task.org_id, req.month, req.year, fn [repo, task] (p int) {
		repo.update_job_progress(task.job_id, task.org_id, p) or {}
	}) or {
		// Échec applicatif : retry à backoff exponentiel puis dead-letter
		schedule_retry_or_fail(mut repo, queue, task, job, err.msg())
		return
	}

	repo.finish_job_done(task.job_id, task.org_id, '{"count": ${run.len}}') or {
		log_error("Jobs: erreur finalisation job ${task.job_id}: ${err}")
	}
	log_info("Jobs: job ${task.job_id} terminé (${run.len} bulletins)")
}

// schedule_retry_or_fail programme le retry exponentiel d'un job en échec ou le
// place en dead-letter (status failed) quand les tentatives sont épuisées.
fn schedule_retry_or_fail(mut repo repository.Repository, queue chan JobTask, task JobTask, job models.Job, err_msg string) {
	attempts := job.attempts + 1
	if attempts >= job.max_attempts {
		repo.fail_job(task.job_id, task.org_id, err_msg, attempts) or {
			log_error("Jobs: erreur dead-letter job ${task.job_id}: ${err}")
		}
		log_error("Jobs: job ${task.job_id} en dead-letter après ${attempts}/${job.max_attempts} tentatives: ${err_msg}")
		return
	}

	backoff_idx := if attempts - 1 < job_retry_backoffs.len { attempts - 1 } else {
		job_retry_backoffs.len - 1
	}
	backoff_secs := job_retry_backoffs[backoff_idx]

	repo.schedule_retry(task.job_id, task.org_id, attempts, job.max_attempts,
		time.now().add_seconds(backoff_secs)) or {
		log_error("Jobs: erreur programmation retry job ${task.job_id}: ${err}")
		return
	}
	log_info("Jobs: retry job ${task.job_id} (tentative ${attempts}/${job.max_attempts}) dans ${backoff_secs}s — ${err_msg}")

	// Ré-enfile la tâche après le backoff sans bloquer la boucle du worker
	spawn requeue_after(queue, task, backoff_secs)
}

// requeue_after attend le backoff (goroutine auxiliaire) puis remet la tâche en file.
fn requeue_after(queue chan JobTask, task JobTask, backoff_secs int) {
	time.sleep(time.second * backoff_secs)
	queue_push(queue, task)
}

// queue_push pousse la tâche dans la file (non bloquante : repoussée au prochain boot).
fn queue_push(queue chan JobTask, task JobTask) {
	queue <- task
}

// recover_pending_after_restart remet en file les jobs restés pending/running
// suite à un arrêt du process. À appeler au démarrage (après init_tables).
pub fn recover_pending_after_restart(mut repo repository.Repository, queue chan JobTask) int {
	n := repo.reset_stale_running()
	pending := repo.get_pending_jobs_for_recovery()
	for p in pending {
		queue_push(queue, JobTask{
			job_id: p.id
			org_id: p.organization_id
			job_type: p.job_type
		})
	}
	if n + pending.len > 0 {
		log_info("Jobs: reprise de ${n + pending.len} jobs en attente au démarrage")
	}
	return n + pending.len
}