module dto

// LoginRequest - Corps de la requête de connexion
pub struct LoginRequest {
pub mut:
	username string
	password string
}

// RegisterRequest - Corps de la requête de création d'un compte employee
// (le rôle et l'organisation sont forcés côté serveur : employee / org 1)
pub struct RegisterRequest {
pub mut:
	username string
	password string
	email    string
}

// LoginResponse - Réponse de connexion avec token JWT
// Si l'utilisateur a activé le MFA, `challenge` = 'totp' et `mfa_token` porte
// un token court à échanger dans POST /auth/login/mfa.
pub struct LoginResponse {
pub mut:
	success   bool
	token     string
	sub       string
	role      string
	org       int
	expires   string
	challenge string
	mfa_token string
}

// AuthUser est renvoyé en JSON après authentification (sans le hash).
pub struct AuthUser {
pub mut:
	id       int
	username string
	role     string
	email    string
}

// ==================== MFA TOTP (Pilier 3) ====================

// MfaLoginRequest - Deuxième étape de connexion (code TOTP ou code de secours).
pub struct MfaLoginRequest {
pub mut:
	mfa_token string
	code      string
}

// MfaEnrollRequest - Activation du MFA (code de validation TOTP + confirmation).
pub struct MfaEnrollRequest {
pub mut:
	code string
}

// MfaEnrollResponse - Résultat de l'enrôlement (secret à renseigner dans l'authenticator, codes à noter).
pub struct MfaEnrollResponse {
pub mut:
	secret       string
	otpauth_uri  string
	backup_codes []string
}

// MfaStatus - État MFA du compte courant.
pub struct MfaStatus {
pub mut:
	enabled            bool
	backup_codes_count int
}

// MfaDisableRequest - Désactivation (mot de passe requis).
pub struct MfaDisableRequest {
pub mut:
	password string
}

// ==================== SSO OIDC (Pilier 3) ====================

// SsoConfig - Configuration OIDC exposée au frontend (sans le client_secret).
pub struct SsoConfig {
pub mut:
	enabled      bool
	issuer       string
	client_id    string
	redirect_uri string
	scopes       string
}
