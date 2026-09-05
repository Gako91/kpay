module dto

import models

// Réponses JSON
pub struct ApiResponse {
pub mut:
	success bool
	data    string
	message string
}

pub struct ErrorResponse {
pub mut:
	success bool
	error_  string @[json: 'error']
}

// Structure pour la requête de calcul de paie individuelle
// Les cotisations CNPS sont chargées depuis la base (pays CI)
pub struct PayrollRequest {
pub mut:
	employee_id int
	month       int
	year        int
}

// Structure pour la requête de paie mensuelle globale
pub struct PayrollRunRequest {
pub mut:
	month int
	year  int
}

// Ligne individuelle pour le Livre de Paie (Payroll Book)
pub struct PayrollBookItem {
pub mut:
	payslip_id   int
	employee_id  int
	matricule    string
	full_name    string
	position     string
	gross_amount i64
	total_taxes  i64
	net_amount   i64
	is_paid      bool
}

// Récapitulatif global du Livre de Paie
pub struct PayrollBookResponse {
pub mut:
	month           int
	year            int
	total_employees int
	total_gross     i64
	total_taxes     i64
	total_net       i64
	items           []PayrollBookItem
}

// Réponse de l'exécution de la paie mensuelle
pub struct RunResponse {
pub mut:
	success  bool
	count    int
	payslips []models.Payslip
}

// Réponse paginée générique
pub struct PageResponse[T] {
pub mut:
	data        []T
	page        int
	page_size   int
	total       int
	total_pages int
}

pub fn error_response(msg string) ErrorResponse {
	return ErrorResponse{
		success: false
		error_: msg
	}
}
