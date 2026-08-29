module models

import time

// Pointage ou heures déclarées
pub struct Timesheet {
pub:
	id           int @[primary; sql: serial]
	employee_id  int
	month        int // 1-12
	year         int
	hours_worked f32
	overtime_h   f32
}

// Primes, bonus ou retenues exceptionnelles
pub struct Adjustment {
pub:
	id          int @[primary; sql: serial]
	employee_id int
	month       int // 1-12 : mois auquel s'applique l'ajustement
	year        int // ex: 2026
	amount      i64 // Positif (prime) ou négatif (retenue)
	description string
	date        time.Time
}
