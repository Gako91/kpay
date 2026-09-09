module services

import models
import repository
import common
import dto
import time
import json2
import crypto.sha256
import crypto.rand
import net.http

// AuthService gère l'authentification des utilisateurs (JWT + MFA + SSO).
pub struct AuthService {
mut:
	repo           repository.Repository
	jwt_secret     string
	jwt_ttl        int
	oidc_issuer    string
	oidc_client_id string
	oidc_client_secret string
	oidc_redirect_uri  string
	oidc_scopes        string
}

pub fn new_auth_service(mut repo repository.Repository, config common.Config) AuthService {
	ttl_hours := if config.jwt_expiration_hours > 0 { config.jwt_expiration_hours } else { 24 }
	return AuthService{
		repo: repo
		jwt_secret: config.jwt_secret
		jwt_ttl: ttl_hours * 3600
		oidc_issuer: config.oidc_issuer
		oidc_client_id: config.oidc_client_id
		oidc_client_secret: config.oidc_client_secret
		oidc_redirect_uri: config.oidc_redirect_uri
		oidc_scopes: config.oidc_scopes
	}
}

// login authentifie un utilisateur et retourne un token JWT (ou un challenge MFA si activé).
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

	// Deuxième étape requise si le MFA TOTP est actif
	if user.mfa_enabled {
		mfa_token := common.generate_jwt(user.username, 'mfa_challenge', user.organization_id, s.jwt_secret, 300, 'kpay-mfa') or {
			return error('Erreur génération challenge MFA: ${err}')
		}
		return dto.LoginResponse{
			success: true
			sub: user.username
			role: user.role
			org: user.organization_id
			challenge: 'totp'
			mfa_token: mfa_token
		}
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

// login_mfa valide le code TOTP / code de secours de la deuxième étape et délivre le JWT final.
pub fn (mut s AuthService) login_mfa(mfa_token string, code string) !dto.LoginResponse {
	claims := common.verify_jwt(mfa_token, s.jwt_secret) or {
		return error('Challenge MFA invalide ou expiré')
	}
	if claims.role != 'mfa_challenge' {
		return error('Challenge MFA invalide')
	}
	user := s.repo.get_user_by_username(claims.sub) or {
		return error('Identifiants invalides')
	}
	if !user.is_active {
		return error('Compte désactivé')
	}
	if !user.mfa_enabled {
		return error('Le MFA n\'est pas activé sur ce compte')
	}

	if !s.validate_mfa_code(user, code) {
		return error('Code MFA invalide')
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

// validate_mfa_code accepte un code TOTP valide ou un code de secours non consommé.
fn (mut s AuthService) validate_mfa_code(user models.User, code string) bool {
	if common.verify_totp(user.mfa_secret, code, 1) {
		return true
	}
	// Codes de secours : comparaison hash + consommation immédiate
	stored := if user.mfa_backup_codes.len > 0 {
		user.mfa_backup_codes.split(',')
	} else {
		[]string{}
	}
	hashed := common.hash_backup_code(code.trim_space().to_upper())
	for i, h in stored {
		if h == hashed && h.len > 0 {
			mut remaining := stored.clone()
			remaining.delete(i)
			s.repo.consume_backup_code(user.id, remaining) or {}
			return true
		}
	}
	return false
}

// mfa_status retourne l'état MFA du compte.
pub fn (s &AuthService) mfa_status(username string) !dto.MfaStatus {
	user := s.repo.get_user_by_username(username) or {
		return error('Compte introuvable')
	}
	count := if user.mfa_backup_codes.len > 0 { user.mfa_backup_codes.split(',').len } else { 0 }
	return dto.MfaStatus{
		enabled: user.mfa_enabled
		backup_codes_count: count
	}
}

// mfa_enroll génère un secret, l'enregistre (désactivé) et retourne l'enrôlement.
pub fn (mut s AuthService) mfa_enroll(username string) !dto.MfaEnrollResponse {
	if s.jwt_secret.len == 0 {
		return error('JWT secret non configuré')
	}
	user := s.repo.get_user_by_username(username) or {
		return error('Compte introuvable')
	}
	if user.mfa_enabled {
		return error('Le MFA est déjà activé sur ce compte')
	}
	secret := common.generate_mfa_secret() or {
		return error('Génération du secret MFA impossible: ${err}')
	}
	backup := common.generate_backup_codes(10) or {
		return error('Génération des codes de secours impossible: ${err}')
	}
	mut hashed := []string{}
	for b in backup {
		hashed << common.hash_backup_code(b)
	}
	uri := common.otpauth_uri(secret, user.username, 'KPay')
	s.repo.set_mfa_fields(user.id, secret, false, hashed.join(',')) or {
		return error('Erreur enregistrement MFA: ${err}')
	}
	log_info("MFA enrôlé pour '${username}' (en attente de validation)")
	return dto.MfaEnrollResponse{
		secret: secret
		otpauth_uri: uri
		backup_codes: backup
	}
}

// mfa_verify valide le premier code TOTP saisi par l'utilisateur et active le MFA.
pub fn (mut s AuthService) mfa_verify(username string, code string) ! {
	user := s.repo.get_user_by_username(username) or {
		return error('Compte introuvable')
	}
	if user.mfa_enabled {
		return error('Le MFA est déjà activé')
	}
	if !common.verify_totp(user.mfa_secret, code, 1) {
		return error('Code de validation invalide')
	}
	s.repo.set_mfa_fields(user.id, user.mfa_secret, true, user.mfa_backup_codes)!
	log_info("MFA activé pour '${username}'")
}

// mfa_disable désactive le MFA après vérification du mot de passe.
pub fn (mut s AuthService) mfa_disable(username string, password string) ! {
	user := s.repo.get_user_by_username(username) or {
		return error('Compte introuvable')
	}
	if !user.mfa_enabled {
		return error('Le MFA n\'est pas activé sur ce compte')
	}
	if !common.verify_password(password, user.password_hash) {
		return error('Mot de passe incorrect')
	}
	s.repo.set_mfa_fields(user.id, '', false, '')!
	log_info("MFA désactivé pour '${username}'")
}

// sso_config retourne la configuration OIDC exposée (sans secret).
pub fn (s &AuthService) sso_config() dto.SsoConfig {
	return dto.SsoConfig{
		enabled: s.sso_enabled()
		issuer: s.oidc_issuer
		client_id: s.oidc_client_id
		redirect_uri: s.oidc_redirect_uri
		scopes: s.oidc_scopes
	}
}

// sso_enabled indique si le SSO OIDC est configuré.
pub fn (s &AuthService) sso_enabled() bool {
	return s.oidc_issuer.len > 0 && s.oidc_client_id.len > 0 && s.oidc_redirect_uri.len > 0
}

// ==================== SSO OIDC — Authorization Code + PKCE ====================

struct SsoEndpoints {
	auth_url     string
	token_url    string
	userinfo_url string
}

// OidcDiscovery - Documents de découverte du fournisseur (endpoints).
struct OidcDiscovery {
	authorization_endpoint string
	token_endpoint         string
	userinfo_endpoint      string
}

// OidcToken - Réponse de l'échange du code d'autorisation.
struct OidcToken {
	access_token string
	id_token     string
}

// OidcUserInfo - Claims du profil utilisateur (userinfo).
struct OidcUserInfo {
	sub            string
	email          string
	email_verified bool
	name           string
}

// sso_discover récupère les endpoints OIDC via la découverte standard.
fn (s &AuthService) sso_discover() !SsoEndpoints {
	issuer := s.oidc_issuer.trim_right('/')
	resp := http.get('${issuer}/.well-known/openid-configuration') or {
		return error('Découverte OIDC impossible (${s.oidc_issuer}): ${err}')
	}
	if resp.status_code != 200 {
		return error('Découverte OIDC refusée (HTTP ${resp.status_code})')
	}
	disc := json2.decode[OidcDiscovery](resp.body) or {
		return error('Réponse de découverte OIDC illisible')
	}
	if disc.authorization_endpoint.len == 0 || disc.token_endpoint.len == 0 || disc.userinfo_endpoint.len == 0 {
		return error('Découverte OIDC incomplète (endpoints manquants)')
	}
	return SsoEndpoints{
		auth_url: disc.authorization_endpoint
		token_url: disc.token_endpoint
		userinfo_url: disc.userinfo_endpoint
	}
}

// sso_authorize_url construit l'URL du fournisseur avec PKCE (state stocké en base).
pub fn (mut s AuthService) sso_authorize_url() !(string, string) {
	eps := s.sso_discover()!
	verifier := s.generate_pkce_verifier() or {
		return error('Génération PKCE impossible: ${err}')
	}
	challenge := common.base64url_encode(sha256.sum(verifier.bytes()))
	state := common.base64url_encode((time.now().unix_nano().str() + '_' + verifier).bytes())

	s.repo.save_sso_state(state, verifier, 600)!

	mut params := 'client_id=${common.url_encode(s.oidc_client_id)}&redirect_uri=${common.url_encode(s.oidc_redirect_uri)}'
	params += '&response_type=code&scope=${common.url_encode(s.oidc_scopes)}&state=${state}'
	params += '&code_challenge=${challenge}&code_challenge_method=S256'
	param_sep := if eps.auth_url.contains('?') { '&' } else { '?' }
	return '${eps.auth_url}${param_sep}${params}', state
}

// sso_exchange_code échange le code d'autorisation (PKCE) contre un JWT KPay.
// Identité vérifiée via userinfo + email match strict avec un compte KPay.
pub fn (mut s AuthService) sso_exchange_code(code string, state string) !dto.LoginResponse {
	st := s.repo.get_sso_state(state) or {
		return error('État SSO invalide ou expiré — relancez la connexion')
	}
	eps := s.sso_discover()!

	form := {
		'grant_type':    'authorization_code'
		'code':          code
		'redirect_uri':  s.oidc_redirect_uri
		'client_id':     s.oidc_client_id
		'client_secret': s.oidc_client_secret
		'code_verifier': st.code_verifier
	}
	resp := http.post_form(eps.token_url, form) or {
		return error('Échange du code OIDC impossible: ${err}')
	}
	if resp.status_code != 200 {
		return error('Échange du code OIDC refusé (HTTP ${resp.status_code}): ${resp.body[0..if resp.body.len > 160 { 160 } else { resp.body.len }]}')
	}
	tok := json2.decode[OidcToken](resp.body) or {
		return error('Réponse token OIDC illisible')
	}
	access_token := tok.access_token
	if access_token.len == 0 {
		return error('Token d\'accès OIDC manquant')
	}

	// Profil vérifié auprès du fournisseur (userinfo) — c'est la source de confiance.
	ui_resp := http.fetch(method: .get, url: eps.userinfo_url, header: http.new_header(key: .authorization, value: 'Bearer ${access_token}')) or {
		return error('Récupération userinfo impossible: ${err}')
	}
	if ui_resp.status_code != 200 {
		return error('userinfo refusé (HTTP ${ui_resp.status_code})')
	}
	profile := json2.decode[OidcUserInfo](ui_resp.body) or {
		return error('userinfo illisible')
	}
	sub := profile.sub
	email := profile.email
	if sub.len == 0 || email.len == 0 {
		return error('Profil SSO incomplet (sub/email manquants)')
	}
	if !profile.email_verified {
		return error('Email non vérifié par le fournisseur SSO')
	}

	// Lien existant ?
	if link := s.repo.find_user_sso('oidc', sub) {
		user := s.repo.get_user_by_id(link.user_id) or {
			return error('Compte lié introuvable')
		}
		if !user.is_active {
			return error('Compte désactivé')
		}
		return s.issue_login(user)
	}

	// Email match strict : un compte KPay actif doit posséder cet email.
	user := s.repo.get_user_by_email_any(email) or {
		log_warn("SSO : aucun compte KPay actif avec l'email '${email}'")
		return error('Aucun compte KPay lié à cet email — contactez votre administrateur')
	}
	s.repo.save_user_sso(models.UserSso{
		user_id: user.id
		provider: 'oidc'
		external_sub: sub
		email: email
	})!
	log_info("Compte externe OIDC lié à '${user.username}' (email ${email})")
	return s.issue_login(user)
}

// issue_login génère le token final pour un utilisateur (utilisé après SSO).
fn (s &AuthService) issue_login(user models.User) dto.LoginResponse {
	token := common.generate_jwt(user.username, user.role, user.organization_id, s.jwt_secret, s.jwt_ttl, 'kpay') or {
		return dto.LoginResponse{
			success: false
			sub: user.username
			role: user.role
			org: user.organization_id
		}
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

// generate_pkce_verifier génère un code_verifier PKCE (43-128 caractères alphanumériques).
fn (s &AuthService) generate_pkce_verifier() !string {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
	mut v := ''
	for i := 0; i < 64; i++ {
		b := rand.bytes(1)!
		idx := int(b[0]) % alphabet.len
		v += alphabet[idx..idx + 1]
	}
	return v
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
