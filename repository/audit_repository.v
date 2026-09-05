module repository

import models
import time

// ==================== AUDIT LOG ====================

// parse_pg_timestamp convertit un timestamp PostgreSQL (stocké en texte)
// en time.Time. Gère les fractions de seconde ("2026-09-05 12:00:00.123").
fn parse_pg_timestamp(s string) time.Time {
	if s.len < 19 {
		return time.Time{}
	}
	// forme de 20 caractères minimum (année-...-sec) ; on ignore fraction/TZ si présentes
	return time.parse(s[..19]) or { time.Time{} }
}

// create_audit_log insère une entrée dans le journal d'audit.
pub fn (mut r Repository) create_audit_log(log models.AuditLog) !int {
	inserted_id := sql r.db {
		insert log into models.AuditLog
	}!
	return inserted_id
}

// get_audit_logs retourne les entrées d'audit triées du plus récent au plus ancien.
// `actor`, `action` et `resource` filtrent le résultat (chaîne vide = aucun filtre).
pub fn (r &Repository) get_audit_logs(actor string, action string, resource string, limit int, offset int) []models.AuditLog {
	mut query := 'SELECT id, actor, action, resource, resource_id, detail, ip, created_at FROM audit_log WHERE 1=1'
	mut params := []string{}
	if actor.len > 0 {
		query += ' AND actor = \$' + (params.len + 1).str()
		params << actor
	}
	if action.len > 0 {
		query += ' AND action = \$' + (params.len + 1).str()
		params << action
	}
	if resource.len > 0 {
		query += ' AND resource = \$' + (params.len + 1).str()
		params << resource
	}
	query += ' ORDER BY id DESC LIMIT \$' + (params.len + 1).str() + ' OFFSET \$' + (params.len + 2).str()
	params << limit.str()
	params << offset.str()

	rows := r.db.exec_param_many(query, params) or { return [] }
	mut logs := []models.AuditLog{}
	for row in rows {
		logs << models.AuditLog{
			id: row.val(0).int()
			actor: row.val(1)
			action: row.val(2)
			resource: row.val(3)
			resource_id: row.val(4).int()
			detail: row.val(5)
			ip: row.val(6)
			created_at: parse_pg_timestamp(row.val(7))
		}
	}
	return logs
}

// count_audit_logs compte les entrées d'audit selon les filtres donnés.
pub fn (r &Repository) count_audit_logs(actor string, action string, resource string) int {
	mut query := 'SELECT COUNT(*) FROM audit_log WHERE 1=1'
	mut params := []string{}
	if actor.len > 0 {
		query += ' AND actor = \$' + (params.len + 1).str()
		params << actor
	}
	if action.len > 0 {
		query += ' AND action = \$' + (params.len + 1).str()
		params << action
	}
	if resource.len > 0 {
		query += ' AND resource = \$' + (params.len + 1).str()
		params << resource
	}
	res := r.db.exec_param_many(query, params) or { return 0 }
	if res.len == 0 {
		return 0
	}
	return res[0].val(0).int()
}
