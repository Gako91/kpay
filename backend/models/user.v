module models

import time

// User représente un compte utilisateur de l'application.
pub struct User {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	username        string @[unique]
	password_hash   string
	role            string // chaîne 'admin' | 'payroll_officer' | 'accountant' | 'employee'
	email           string
	is_active       bool @[default: true]
	created_at      ?time.Time
}
