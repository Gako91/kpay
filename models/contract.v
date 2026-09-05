module models

import time

// Paramètres de rémunération (Contrat)
pub struct Contract {
pub:
	id          int @[primary; sql: serial]
	employee_id int
	base_salary i64 // Salaire de base en FCFA (unités entières, ex: 400000 = 400 000 FCFA)
	hourly_rate i64 // Utile pour les heures supplémentaires
	start_date  time.Time
	end_date    ?time.Time
	currency    string // Devise par défaut: XOF
}
