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

// Réponse de l'exécution de la paie mensuelle
pub struct RunResponse {
pub mut:
	success  bool
	count    int
	payslips []models.Payslip
}


pub fn error_response(msg string) ErrorResponse {
	return ErrorResponse{
		success: false
		error_:  msg
	}
}
