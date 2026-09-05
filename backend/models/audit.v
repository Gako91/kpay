module models

import time

// Entrée du journal d'audit — trace une action sensible de l'application.
@[table: 'audit_log']
pub struct AuditLog {
pub:
	id          int @[primary; sql: serial]
	actor       string // Utilisateur ayant effectué l'action (JWT sub)
	action      string // login, register, employee.create, payroll.run, payslip.approve...
	resource    string // Type de ressource touchée (employee, payslip, user...)
	resource_id int
	detail      string // Détails complémentaires
	ip          string // Adresse IP source
	created_at  time.Time
}

// Statuts de workflow (alias courts, compatibles avec models.payslip)
