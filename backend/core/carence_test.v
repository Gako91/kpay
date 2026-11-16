module core

import time
import models

fn sick(y int, m int, d int, y2 int, m2 int, d2 int, status string) models.LeaveRequest {
	return models.LeaveRequest{
		leave_type: 'maladie'
		status: status
		start_date: time.Time{ year: y, month: m, day: d }
		end_date: time.Time{ year: y2, month: m2, day: d2 }
	}
}

fn test_carence_inside_month() {
	// Arrêt du 10 au 20 mars, carence 3 jours : 10, 11, 12
	assert carence_days_in_month([sick(2026, 3, 10, 2026, 3, 20, 'approuve')], 3, 3, 2026) == 3
	// Rien en avril
	assert carence_days_in_month([sick(2026, 3, 10, 2026, 3, 20, 'approuve')], 3, 4, 2026) == 0
}

fn test_carence_short_leave_and_filters() {
	// Arrêt d'un jour : un seul jour de carence
	assert carence_days_in_month([sick(2026, 3, 10, 2026, 3, 10, 'approuve')], 3, 3, 2026) == 1
	// Non approuvé, ou autre type : ignoré
	assert carence_days_in_month([sick(2026, 3, 10, 2026, 3, 20, 'en_attente')], 3, 3, 2026) == 0
	mut cp := sick(2026, 3, 10, 2026, 3, 20, 'approuve')
	cp = models.LeaveRequest{
		...cp
		leave_type: 'conge_paye'
	}
	assert carence_days_in_month([cp], 3, 3, 2026) == 0
	// Carence désactivée
	assert carence_days_in_month([sick(2026, 3, 10, 2026, 3, 20, 'approuve')], 0, 3, 2026) == 0
}

fn test_carence_across_months_and_several_leaves() {
	// Arrêt du 30 janvier au 10 février, carence 3 : 30, 31 janvier puis 1er février
	l := sick(2026, 1, 30, 2026, 2, 10, 'approuve')
	assert carence_days_in_month([l], 3, 1, 2026) == 2
	assert carence_days_in_month([l], 3, 2, 2026) == 1
	// Deux arrêts dans le mois : la carence s'applique à chacun
	two := [sick(2026, 3, 2, 2026, 3, 5, 'approuve'), sick(2026, 3, 20, 2026, 3, 25, 'approuve')]
	assert carence_days_in_month(two, 3, 3, 2026) == 6
}

fn test_carence_deduction() {
	assert carence_deduction(450000, 3) == 45000
	assert carence_deduction(400000, 1) == 13333
	assert carence_deduction(400000, 0) == 0
}
