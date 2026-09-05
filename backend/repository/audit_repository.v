module repository

import models

// ==================== AUDIT LOG ====================

// create_audit_log insère une entrée dans le journal d'audit.
pub fn (mut r Repository) create_audit_log(log models.AuditLog) !int {
	inserted_id := sql r.db {
		insert log into models.AuditLog
	}!
	return inserted_id
}

// filter_audit_logs applique les filtres optionnels sur une liste d'entrées d'audit.
fn filter_audit_logs(logs []models.AuditLog, actor string, action string, resource string) []models.AuditLog {
	mut filtered := []models.AuditLog{}
	for log in logs {
		if actor.len > 0 && log.actor != actor {
			continue
		}
		if action.len > 0 && log.action != action {
			continue
		}
		if resource.len > 0 && log.resource != resource {
			continue
		}
		filtered << log
	}
	return filtered
}

// get_audit_logs retourne les entrées d'audit triées du plus récent au plus ancien.
// `actor`, `action` et `resource` filtrent le résultat (chaîne vide = aucun filtre).
pub fn (r &Repository) get_audit_logs(actor string, action string, resource string, limit int, offset int) []models.AuditLog {
	all_logs := sql r.db {
		select from models.AuditLog order by id desc
	} or { [] }
	filtered := filter_audit_logs(all_logs, actor, action, resource)
	start := if offset < filtered.len { offset } else { filtered.len }
	end := start + limit
	if start >= filtered.len {
		return []models.AuditLog{}
	}
	if end > filtered.len {
		return filtered[start..]
	}
	return filtered[start..end]
}

// count_audit_logs compte les entrées d'audit selon les filtres donnés.
pub fn (r &Repository) count_audit_logs(actor string, action string, resource string) int {
	all_logs := sql r.db {
		select from models.AuditLog
	} or { [] }
	return filter_audit_logs(all_logs, actor, action, resource).len
}
