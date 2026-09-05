module services

import models
import repository
import time

// AuditService centralise l'écriture et la lecture du journal d'audit.
pub struct AuditService {
mut:
	repo repository.Repository
}

pub fn new_audit_service(mut repo repository.Repository) AuditService {
	return AuditService{
		repo: repo
	}
}

// record ajoute une entrée au journal d'audit (best effort : n'échoue pas la requête).
pub fn (s &AuditService) record(actor string, action string, resource string, resource_id int, detail string, ip string) {
	entry := models.AuditLog{
		actor: actor
		action: action
		resource: resource
		resource_id: resource_id
		detail: detail
		ip: ip
		created_at: time.now()
	}
	mut repo := s.repo
	repo.create_audit_log(entry) or {
		log_warn('Audit non enregistré (${action}): ${err}')
	}
}

// list retourne les entrées d'audit filtrées, paginées du plus récent au plus ancien.
pub fn (s &AuditService) list(actor string, action string, resource string, page int, page_size int) ([]models.AuditLog, int) {
	total := s.repo.count_audit_logs(actor, action, resource)
	logs := s.repo.get_audit_logs(actor, action, resource, page_size, (page - 1) * page_size)
	return logs, total
}
