module models

import time

// Paramètres de rémunération (Contrat)
pub struct Contract {
pub:
	id          int @[primary; sql: serial]
	employee_id int
	base_salary i64 // En centimes (ex: 400000 = 4000.00 FCFA)
	hourly_rate i64 // Utile pour les heures supplémentaires
	start_date  time.Time
	end_date    ?time.Time
	currency    string // Devise par défaut: XOF
}
