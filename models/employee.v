module models

// Identité de base
pub struct Employee {
pub:
	id         int @[primary; sql: serial]
	first_name string
	last_name  string
	email      string @[unique]
	is_active  bool   @[default: true]
}
