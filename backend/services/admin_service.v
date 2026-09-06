module services

import dto
import models
import repository
import common
import time

// AdminService gère les opérations d'administration plateforme (onboarding de tenants).
pub struct AdminService {
mut:
	repo repository.Repository
}

pub fn new_admin_service(mut repo repository.Repository) AdminService {
	return AdminService{
		repo: repo
	}
}

// create_organization_with_admin crée une organisation et son utilisateur admin
// dans une transaction unique (tout ou rien).
pub fn (mut s AdminService) create_organization_with_admin(req dto.CreateOrganizationRequest) !dto.CreateOrganizationResponse {
	// Validation métier
	if req.name.trim_space().len < 2 {
		return error("Nom d'organisation invalide (min 2 caractères)")
	}
	if req.admin_username.trim_space().len < 3 {
		return error("Nom d'utilisateur admin invalide (min 3 caractères)")
	}
	if req.admin_password.len < 6 {
		return error('Mot de passe admin trop court (min 6 caractères)')
	}

	if s.repo.get_organization_by_name(req.name) != none {
		return error("L'organisation '${req.name}' existe déjà")
	}
	if _ := s.repo.get_user_by_username(req.admin_username) {
		return error("Le nom d'utilisateur '${req.admin_username}' est déjà pris")
	}

	currency := if req.currency.trim_space().len > 0 { req.currency.trim_space() } else { 'XOF' }
	email := if req.admin_email.trim_space().len > 0 {
		req.admin_email.trim_space()
	} else {
		'${req.admin_username}@${req.name.replace(' ', '').to_lower()}.local'
	}

	s.repo.begin_transaction() or { return error("Impossible de démarrer la transaction: ${err}") }

	org_id := s.repo.create_organization(models.Organization{
		name: req.name.trim_space()
		tax_id: req.tax_id.trim_space()
		currency: currency
		created_at: time.now()
	}) or {
		s.repo.rollback()
		return error("Échec de la création de l'organisation: ${err}")
	}

	user_id := s.repo.create_user(models.User{
		username: req.admin_username.trim_space()
		password_hash: common.hash_password(req.admin_password)
		role: 'admin'
		email: email
		organization_id: org_id
		is_active: true
		created_at: time.now()
	}) or {
		s.repo.rollback()
		return error("Échec de la création de l'admin: ${err}")
	}

	s.repo.commit() or {
		s.repo.rollback()
		return error("Échec du commit: ${err}")
	}

	log_info("Organisation '${req.name}' créée (org ${org_id}) avec admin '${req.admin_username}' (user ${user_id})")
	return dto.CreateOrganizationResponse{
		success: true
		org_id: org_id
		name: req.name
		admin_username: req.admin_username
		message: "Organisation '${req.name}' créée, admin '${req.admin_username}' prêt"
	}
}

// get_all_organizations liste les tenants (plateforme uniquement).
pub fn (s &AdminService) get_all_organizations() []models.Organization {
	return s.repo.get_all_organizations()
}