module services

import models
import repository
import common
import dto
import time

// AuthService gère l'authentification des utilisateurs (JWT).
pub struct AuthService {
mut:
	repo       repository.Repository
	jwt_secret string
	jwt_ttl    int
}

pub fn new_auth_service(mut repo repository.Repository, config common.Config) AuthService {
	ttl_hours := if config.jwt_expiration_hours > 0 { config.jwt_expiration_hours } else { 24 }
	return AuthService{
		repo: repo
		jwt_secret: config.jwt_secret
		jwt_ttl: ttl_hours * 3600
	}
}

// login authentifie un utilisateur et retourne un token JWT.
pub fn (s &AuthService) login(username string, password string) !dto.LoginResponse {
	if s.jwt_secret.len == 0 {
		return error('JWT secret non configuré')
	}
	user := s.repo.get_user_by_username(username) or {
		return error('Identifiants invalides')
	}
	if !user.is_active {
		return error('Compte désactivé')
	}
	if !common.verify_password(password, user.password_hash) {
		return error('Identifiants invalides')
	}

	token := common.generate_jwt(user.username, user.role, user.organization_id, s.jwt_secret, s.jwt_ttl, 'kpay') or {
		return error('Erreur génération token: ${err}')
	}

	return dto.LoginResponse{
		success: true
		token: token
		sub: user.username
		role: user.role
		org: user.organization_id
		expires: time.now().add_seconds(s.jwt_ttl).format_ss()
	}
}

// register crée un compte employee au sein de l'organisation 1.
// L'onboarding d'un nouveau tenant passe par l'endpoint admin (création d'organisation + admin dédié).
pub fn (mut s AuthService) register(username string, password string, email string) !int {
	if s.jwt_secret.len == 0 {
		return error('JWT secret non configuré')
	}
	user := models.User{
		username: username
		password_hash: common.hash_password(password)
		role: 'employee'
		email: email
		organization_id: 1
		is_active: true
		created_at: time.now()
	}
	inserted_id := s.repo.create_user(user)!
	// Auto-lien ESS : si un dossier employé existe avec le même email dans l'org,
	// on associe le compte pour permettre /me/payslips.
	linked_emp := s.repo.link_employee_by_email(1, inserted_id, email) or { 0 }
	if linked_emp > 0 {
		log_info("Compte '${username}' lié au dossier employé ${linked_emp} (email concordant)")
	}
	log_info('Utilisateur créé: ${username} (employee) org=1')
	return inserted_id
}

// get_user retourne un utilisateur par identifiant (sans hash).
pub fn (s &AuthService) get_user(id int) !dto.AuthUser {
	user := s.repo.get_user_by_id(id) or {
		return error('Utilisateur non trouvé')
	}
	return dto.AuthUser{
		id: user.id
		username: user.username
		role: user.role
		email: user.email
	}
}
