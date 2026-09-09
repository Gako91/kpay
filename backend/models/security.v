module models

import time

// Permission représente une action granulaire de l'application (Pilier 3 — RBAC).
// La table est créée et seedée par la migration 014 (source de vérité du schéma).
@[table: 'permission']
pub struct Permission {
pub:
	code        string @[primary]
	label       string
	module_name string
}

// RolePermission mappe un rôle vers la permission qu'il possède.
// (index unique (role, permission_code) posé par la migration 014)
@[table: 'role_permission']
pub struct RolePermission {
pub:
	id              int @[primary; sql: serial]
	role            string
	permission_code string
}

// Rôles natifs de l'application (le rôle admin possède toutes les permissions, implicite).
pub const default_roles = ['admin', 'payroll_officer', 'accountant', 'manager', 'employee']

// UserSso lie un compte externe (OIDC/OAuth2) à un utilisateur KPay.
@[table: 'user_sso']
pub struct UserSso {
pub:
	id            int @[primary; sql: serial]
	user_id       int
	provider      string
	external_sub  string
	email         string
	created_at    ?time.Time
}

// SsoState stocke le code_verifier PKCE associé à l'état OIDC (Authorization Code flow).
@[table: 'sso_state']
pub struct SsoState {
pub:
	state         string @[primary]
	code_verifier string
	created_at    ?time.Time
	expires_at    ?time.Time
}