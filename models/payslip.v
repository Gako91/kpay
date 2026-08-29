module models

import time

// Bulletin de paie généré
pub struct Payslip {
pub:
	id           int @[primary; sql: serial]
	employee_id  int
	period_start time.Time
	period_end   time.Time
	gross_amount i64
	total_taxes  i64
	net_amount   i64
	is_paid      bool @[default: false]
	paid_at      ?time.Time
	pdf_path     string
}

// Résultat d'un calcul de paie (runtime)
pub struct PayRun {
pub:
	employee_id int
	gross_pay   i64
	tax_amount  i64
	net_pay     i64
	date        string
}
