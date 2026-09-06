module repository

import models
import time

// ==================== PROFILE CHANGE REQUESTS ====================

// create_profile_change_request inscrit une demande de modification du profil employé.
pub fn (mut r Repository) create_profile_change_request(req models.ProfileChangeRequest) !int {
	inserted_id := sql r.db {
		insert req into models.ProfileChangeRequest
	}!
	return inserted_id
}

// get_profile_change_requests liste les demandes d'une organisation, filtrées par statut (vide = toutes).
pub fn (r &Repository) get_profile_change_requests(org_id int, status string) []models.ProfileChangeRequest {
	if status.len == 0 {
		return sql r.db {
			select from models.ProfileChangeRequest where organization_id == org_id order by requested_at desc
		} or { [] }
	}
	return sql r.db {
		select from models.ProfileChangeRequest where organization_id == org_id && status == status order by requested_at desc
	} or { [] }
}

// get_profile_change_requests_by_employee liste les demandes d'un employé (ESS).
pub fn (r &Repository) get_profile_change_requests_by_employee(emp_id int, org_id int) []models.ProfileChangeRequest {
	return sql r.db {
		select from models.ProfileChangeRequest where employee_id == emp_id && organization_id == org_id order by requested_at desc
	} or { [] }
}

// get_profile_change_request_by_id récupère une demande (scopée org).
pub fn (r &Repository) get_profile_change_request_by_id(id int, org_id int) ?models.ProfileChangeRequest {
	result := sql r.db {
		select from models.ProfileChangeRequest where id == id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// has_pending_profile_change vérifie qu'une demande est déjà en attente pour le champ.
pub fn (r &Repository) has_pending_profile_change(emp_id int, field_name string, org_id int) bool {
	result := sql r.db {
		select from models.ProfileChangeRequest where employee_id == emp_id && field_name == field_name && status == 'en_attente' && organization_id == org_id limit 1
	} or { [] }
	return result.len > 0
}

// get_pending_rib_changes retourne les employee_id ayant une demande de RIB/BIC en attente (SEPA).
pub fn (r &Repository) get_pending_rib_changes(org_id int) map[int][]string {
	mut pending := map[int][]string{}
	requests := sql r.db {
		select from models.ProfileChangeRequest where organization_id == org_id && status == 'en_attente'
	} or { [] }
	for req in requests {
		if req.field_name == 'iban' || req.field_name == 'bic' {
			pending[req.employee_id] << req.field_name
		}
	}
	return pending
}

// approve_profile_change_request valide une demande (statut + réviseur + horodatage).
pub fn (mut r Repository) approve_profile_change_request(id int, reviewer string, org_id int) ! {
	sql r.db {
		update models.ProfileChangeRequest set status = 'approuve', reviewed_by = reviewer, reviewed_at = time.now() where id == id && organization_id == org_id
	}!
}

// reject_profile_change_request refuse une demande (statut + motif + réviseur + horodatage).
pub fn (mut r Repository) reject_profile_change_request(id int, reviewer string, reason string, org_id int) ! {
	sql r.db {
		update models.ProfileChangeRequest set status = 'refuse', rejection_reason = reason, reviewed_by = reviewer, reviewed_at = time.now() where id == id && organization_id == org_id
	}!
}