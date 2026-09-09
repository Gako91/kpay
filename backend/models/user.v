module models

import time

// User représente un compte utilisateur de l'application.
pub struct User {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	username        string @[unique]
	password_hash   string
	role            string // chaîne 'admin' | 'payroll_officer' | 'accountant' | 'manager' | 'employee'
	email           string
	is_active       bool @[default: true]
	// Pilier 3 — MFA TOTP
	mfa_secret       string @[default: '']
	mfa_enabled      bool   @[default: false]
	mfa_backup_codes string @[default: '']
	created_at       ?time.Time
}
