module models

import time

// Statuts du workflow d'approbation d'un bulletin
pub const status_brouillon = 'brouillon' // Généré, pas encore transmis
pub const status_soumis = 'soumis' // Transmis pour approbation
pub const status_approuve = 'approuve' // Validé par un responsable
pub const status_rejete = 'rejete' // Refusé, retour en brouillon
pub const status_paye = 'paye' // Virement effectué

// Bulletin de paie généré
pub struct Payslip {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	employee_id     int
	period_start    time.Time
	period_end      time.Time
	gross_amount    i64
	total_taxes     i64
	net_amount      i64
	is_paid         bool @[default: false]
	paid_at         ?time.Time
	pdf_path        string
	status          string
	approved_by     string
	approved_at     ?time.Time
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
