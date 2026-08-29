module dto

import models

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
}

// ==================== PAYROLL ====================

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
