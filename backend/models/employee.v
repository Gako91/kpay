module models

// Identité de base
pub struct Employee {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	first_name      string
	last_name       string
	email           string @[unique]
	iban            string
	bic             string
	phone           string
	address         string
	tax_parts       f32 @[default: 1.0] // Nombre de parts fiscales pour l'IGR (ex: 1.0, 1.5, 2.0, 2.5...)
	user_id         ?int // Compte utilisateur lié pour l'ESS (/me/...)
	is_active       bool @[default: true]
}
