module dto

import models
import time

// ==================== HELPERS ====================

// validate_id vérifie qu'un ID d'URL est strictement positif
pub fn validate_id(id int, field_name string) ! {
	if id <= 0 {
		return error("Validation échouée : '${field_name}' doit être un entier positif (reçu: ${id})")
	}
}

// validate_month vérifie qu'un mois est dans l'intervalle [1, 12]
fn validate_month(month int) ! {
	if month < 1 || month > 12 {
		return error("Validation échouée : 'month' doit être compris entre 1 et 12 (reçu: ${month})")
	}
}

// validate_year vérifie qu'une année est dans un intervalle raisonnable [2000, 2100]
fn validate_year(year int) ! {
	if year < 2000 || year > 2100 {
		return error("Validation échouée : 'year' doit être compris entre 2000 et 2100 (reçu: ${year})")
	}
}

// validate_email vérifie un format d'email minimal (présence de '@' et d'un '.' après)
fn validate_email(email string) ! {
	if email.len == 0 {
		return error("Validation échouée : 'email' ne peut pas être vide")
	}
	at_idx := email.index('@') or {
		return error("Validation échouée : 'email' invalide — doit contenir '@'")
	}
	after_at := email[at_idx + 1..]
	if !after_at.contains('.') || after_at.ends_with('.') {
		return error("Validation échouée : 'email' invalide — domaine incorrect (reçu: ${email})")
	}
}

// validate_string_field vérifie qu'une chaîne n'est pas vide et respecte les bornes de longueur
fn validate_string_field(value string, field_name string, min_len int, max_len int) ! {
	trimmed := value.trim_space()
	if trimmed.len < min_len {
		return error("Validation échouée : '${field_name}' doit contenir au moins ${min_len} caractère(s) (reçu: '${trimmed}')")
	}
	if trimmed.len > max_len {
		return error("Validation échouée : '${field_name}' ne doit pas dépasser ${max_len} caractères")
	}
}

// ==================== EMPLOYEES ====================

// validate_employee valide les champs d'un employé avant création
pub fn validate_employee(emp models.Employee) ! {
	validate_string_field(emp.first_name, 'first_name', 2, 100)!
	validate_string_field(emp.last_name, 'last_name', 2, 100)!
	validate_email(emp.email)!
	if emp.cnps_number.len > 0 && !is_valid_cnps_number(emp.cnps_number) {
		return error("Validation échouée : 'cnps_number' doit comporter exactement 12 chiffres")
	}
	if emp.birth_date.len > 0 {
		validate_iso_date(emp.birth_date, 'birth_date')!
	}
	if emp.salary_type !in ['', 'M', 'J', 'H'] {
		return error("Validation échouée : 'salary_type' doit valoir M (mensuel), J (journalier) ou H (horaire)")
	}
}

// normalize_cnps_number retire espaces, tirets et points d'un n° CNPS saisi.
pub fn normalize_cnps_number(raw string) string {
	return raw.replace(' ', '').replace('-', '').replace('.', '').trim_space()
}

// is_valid_cnps_number vérifie un n° CNPS normalisé : exactement 12 chiffres.
pub fn is_valid_cnps_number(n string) bool {
	return n.len == 12 && n.bytes().all(it.is_digit())
}

// validate_iso_date vérifie une date 'YYYY-MM-DD' existante (ex: pas de 31/02).
pub fn validate_iso_date(value string, field string) ! {
	t := time.parse_format(value, 'YYYY-MM-DD') or {
		return error("Validation échouée : '${field}' doit être une date au format YYYY-MM-DD")
	}
	if t.custom_format('YYYY-MM-DD') != value {
		return error("Validation échouée : '${field}' n'est pas une date valide")
	}
}

// ==================== CONTRACTS ====================

// validate_contract valide les champs d'un contrat avant création
pub fn validate_contract(c models.Contract) ! {
	validate_id(c.employee_id, 'employee_id')!
	if c.base_salary <= 0 {
		return error("Validation échouée : 'base_salary' doit être supérieur à 0")
	}
	if c.hourly_rate < 0 {
		return error("Validation échouée : 'hourly_rate' ne peut pas être négatif")
	}
}

// validate vérifie les champs d'une requête de calcul de paie individuelle
pub fn (r PayrollRequest) validate() ! {
	validate_id(r.employee_id, 'employee_id')!
	validate_month(r.month)!
	validate_year(r.year)!
}

// validate vérifie les champs d'une requête de paie mensuelle globale
pub fn (r PayrollRunRequest) validate() ! {
	validate_month(r.month)!
	validate_year(r.year)!
}

// ==================== TIMESHEETS ====================

// validate_timesheet vérifie les champs d'un timesheet
pub fn validate_timesheet(ts models.Timesheet) ! {
	validate_id(ts.employee_id, 'employee_id')!
	validate_month(ts.month)!
	validate_year(ts.year)!
	if ts.hours_worked < 0 || ts.hours_worked > 744 {
		return error("Validation échouée : 'hours_worked' doit être compris entre 0 et 744")
	}
	if ts.overtime_h < 0 {
		return error("Validation échouée : 'overtime_h' ne peut pas être négatif")
	}
}

// ==================== ADJUSTMENTS ====================

// validate_adjustment vérifie les champs d'un ajustement (prime/retenue)
pub fn validate_adjustment(a models.Adjustment) ! {
	validate_id(a.employee_id, 'employee_id')!
	validate_month(a.month)!
	validate_year(a.year)!
	if a.amount == 0 {
		return error("Validation échouée : 'amount' ne peut pas être nul")
	}
	validate_string_field(a.description, 'description', 2, 255)!
}

// ==================== AUTH ====================

// validate vérifie les champs d'une requête de connexion
pub fn (r LoginRequest) validate() ! {
	validate_string_field(r.username, 'username', 3, 100)!
	if r.password.len < 6 {
		return error("Validation échouée : 'password' doit contenir au moins 6 caractères")
	}
}

// validate vérifie les champs d'une requête d'enregistrement (compte employee publique)
pub fn (r RegisterRequest) validate() ! {
	validate_string_field(r.username, 'username', 3, 100)!
	if r.password.len < 6 {
		return error("Validation échouée : 'password' doit contenir au moins 6 caractères")
	}
	validate_email(r.email)!
}

// validate vérifie les champs d'une requête de création d'organisation (plateforme)
pub fn (r CreateOrganizationRequest) validate() ! {
	validate_string_field(r.name, 'name', 2, 200)!
	if r.admin_username.trim_space().len < 3 {
		return error("Validation échouée : 'admin_username' doit contenir au moins 3 caractères")
	}
	if r.admin_password.len < 6 {
		return error("Validation échouée : 'admin_password' doit contenir au moins 6 caractères")
	}
	if r.admin_email.trim_space().len > 0 {
		validate_email(r.admin_email)!
	}
}
