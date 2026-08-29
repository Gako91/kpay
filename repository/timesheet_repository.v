module repository

import models

// ==================== TIMESHEETS ====================

pub fn (r &Repository) get_timesheet(emp_id int, month int, year int) ?models.Timesheet {
	result := sql r.db {
		select from models.Timesheet where employee_id == emp_id && month == month && year == year limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_timesheet(ts models.Timesheet) !int {
	inserted_id := sql r.db {
		insert ts into models.Timesheet
	}!
	return inserted_id
}

// ==================== ADJUSTMENTS ====================

// get_adjustments_for_period retourne uniquement les ajustements du mois/année indiqués.
// À utiliser pour les calculs de paie afin d'éviter de réappliquer les primes des mois passés.
pub fn (r &Repository) get_adjustments_for_period(emp_id int, month int, year int) []models.Adjustment {
	return sql r.db {
		select from models.Adjustment where employee_id == emp_id && month == month && year == year
	} or { [] }
}

// get_adjustments retourne tous les ajustements d'un employé (usage général / historique).
pub fn (r &Repository) get_adjustments(emp_id int) []models.Adjustment {
	return sql r.db {
		select from models.Adjustment where employee_id == emp_id
	} or { [] }
}

pub fn (mut r Repository) create_adjustment(adj models.Adjustment) !int {
	inserted_id := sql r.db {
		insert adj into models.Adjustment
	}!
	return inserted_id
}
