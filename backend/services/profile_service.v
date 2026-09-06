module services

import dto
import models
import repository
import time

// ProfileService gère le workflow de modification des informations personnelles
// (ESS → demande → approbation RH → application au dossier employé).
pub struct ProfileService {
mut:
	repo repository.Repository
}

pub fn new_profile_service(mut repo repository.Repository) ProfileService {
	return ProfileService{
		repo: repo
	}
}

// allowed_fields liste les champs modifiables par l'employé via le workflow de validation RH.
const profile_allowed_fields = ['iban', 'bic', 'phone', 'address', 'tax_parts']

// request_change enregistre une demande de modification pour l'employé (état en_attente).
pub fn (mut s ProfileService) request_change(emp models.Employee, field_name string, new_value string, org_id int) !models.ProfileChangeRequest {
	if !profile_allowed_fields.contains(field_name) {
		return error("Champ non modifiable: '${field_name}'")
	}
	trimmed := new_value.trim_space()
	if trimmed.len == 0 {
		return error("La nouvelle valeur du champ '${field_name}' ne peut pas être vide")
	}
	// Lecture de l'ancienne valeur depuis le dossier employé courant
	old_value := match field_name {
		'iban' {
			emp.iban
		}
		'bic' {
			emp.bic
		}
		'phone' {
			emp.phone
		}
		'address' {
			emp.address
		}
		'tax_parts' {
			emp.tax_parts.str()
		}
		else {
			''
		}
	}

	if old_value == trimmed {
		return error("La valeur du champ '${field_name}' est déjà '${trimmed}'")
	}
	if s.repo.has_pending_profile_change(emp.id, field_name, org_id) {
		return error("Une demande de modification du champ '${field_name}' est déjà en attente de validation")
	}

	id := s.repo.create_profile_change_request(models.ProfileChangeRequest{
		organization_id: org_id
		employee_id: emp.id
		field_name: field_name
		old_value: old_value
		new_value: trimmed
		status: 'en_attente'
		requested_at: time.now()
	})!
	req := s.repo.get_profile_change_request_by_id(id, org_id) or {
		return error("Demande créée mais introuvable (id ${id})")
	}
	log_info("Profil: demande ${id} de l'employé ${emp.id} (org ${org_id}) — ${field_name}: '${old_value}' → '${trimmed}'")
	return req
}

// list_requests retourne les demandes d'une organisation (filtre statut optionnel).
pub fn (s &ProfileService) list_requests(org_id int, status string) []models.ProfileChangeRequest {
	return s.repo.get_profile_change_requests(org_id, status)
}

// approve valide une demande et applique la modification au dossier employé.
pub fn (mut s ProfileService) approve(req_id int, reviewer string, org_id int) !models.ProfileChangeRequest {
	req := s.repo.get_profile_change_request_by_id(req_id, org_id) or {
		return error('Demande de modification introuvable')
	}
	if req.status != 'en_attente' {
		return error("Seules les demandes 'en_attente' peuvent être approuvées (état actuel: ${req.status})")
	}
	emp := s.repo.get_employee_by_id(req.employee_id, org_id) or {
		return error('Employé lié à la demande introuvable')
	}
	s.repo.update_employee_field(emp.id, org_id, req.field_name, req.new_value)!
	s.repo.approve_profile_change_request(req.id, reviewer, org_id)!

	log_info("Profil: approbation RH ('${reviewer}') de la demande ${req.id} (employé ${emp.id}) — ${req.field_name} → ${req.new_value}")
	return s.repo.get_profile_change_request_by_id(req.id, org_id) or {
		return error('Demande introuvable après approbation')
	}
}

// reject refuse une demande sans appliquer de modification.
pub fn (mut s ProfileService) reject(req_id int, reviewer string, reason string, org_id int) !models.ProfileChangeRequest {
	req := s.repo.get_profile_change_request_by_id(req_id, org_id) or {
		return error('Demande de modification introuvable')
	}
	if req.status != 'en_attente' {
		return error("Seules les demandes 'en_attente' peuvent être refusées (état actuel: ${req.status})")
	}
	trimmed_reason := reason.trim_space()
	if trimmed_reason.len == 0 {
		return error("Un motif de refus est obligatoire")
	}
	s.repo.reject_profile_change_request(req.id, reviewer, trimmed_reason, org_id)!
	log_info("Profil: refus RH ('${reviewer}') de la demande ${req.id} — motif: '${trimmed_reason}'")
	return s.repo.get_profile_change_request_by_id(req.id, org_id) or {
		return error('Demande introuvable après refus')
	}
}

// approve_reject_dto normalise la réponse de workflow pour l'API (DTO).
pub fn profile_review_response(req models.ProfileChangeRequest, message string) dto.ApiResponse {
	return dto.ApiResponse{
		success: true
		data: req.field_name
		message: message
	}
}