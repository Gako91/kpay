module models

import time

// Statuts de cycle de vie d'un job de file de traitement (Pilier 4)
pub const job_pending = 'pending'
pub const job_running = 'running'
pub const job_done = 'done'
pub const job_failed = 'failed'
pub const job_cancelled = 'cancelled'

// Types de jobs supportés
pub const job_type_payroll_run = 'payroll.run'

// Job représente une tâche de fond asynchrone (file de traitement).
// Suivi temps réel via progress (0-100) et statut ; reprise/retry gérée par
// attempts/max_attempts/next_retry_at (backoff exponentiel, dead-letter si épuisé).
pub struct Job {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	job_type        string // ex: payroll.run
	status          string // pending | running | done | failed | cancelled
	progress        int @[default: 0]
	payload         string // paramètres JSON ({month, year})
	result          string // résultat JSON (ex: {"count": N})
	error_          string @[json: 'error'] // message d'échec (dead-letter)
	attempts        int @[default: 0]
	max_attempts    int @[default: 3]
	next_retry_at   ?time.Time // prochain retry programmé (backoff exponentiel)
	created_by      string
	created_at      time.Time
	started_at      ?time.Time
	finished_at     ?time.Time
}