module models

import time

// LeaveRequest représente une demande de congé ou d'absence d'un employé.
pub struct LeaveRequest {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	employee_id     int
	leave_type      string // 'conge_paye', 'rtt', 'maladie', 'sans_solde'
	start_date      time.Time
	end_date        time.Time
	days_count      f32
	reason          string
	status          string // 'en_attente', 'approuve', 'refuse'
	approved_by     string
	created_at      ?time.Time
}
