module repository

import models

// ==================== TIMESHEETS ====================

pub fn (r &Repository) get_timesheet(emp_id int, month int, year int, org_id int) ?models.Timesheet {
	result := sql r.db {
		select from models.Timesheet where employee_id == emp_id && month == month && year == year && organization_id == org_id limit 1
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

pub fn (mut r Repository) update_timesheet(ts models.Timesheet, org_id int) ! {
	sql r.db {
		update models.Timesheet set hours_worked = ts.hours_worked, overtime_h = ts.overtime_h where id == ts.id && organization_id == org_id
	}!
}

pub fn (mut r Repository) delete_timesheet(ts_id int, org_id int) ! {
	sql r.db {
		delete from models.Timesheet where id == ts_id && organization_id == org_id
	}!
}

// ==================== ADJUSTMENTS ====================

// get_adjustments_for_period retourne uniquement les ajustements du mois/année indiqués.
// À utiliser pour les calculs de paie afin d'éviter de réappliquer les primes des mois passés.
pub fn (r &Repository) get_adjustments_for_period(emp_id int, month int, year int, org_id int) []models.Adjustment {
	return sql r.db {
		select from models.Adjustment where employee_id == emp_id && month == month && year == year && organization_id == org_id
	} or { [] }
}

// get_adjustments retourne tous les ajustements d'un employé (usage général / historique).
pub fn (r &Repository) get_adjustments(emp_id int, org_id int) []models.Adjustment {
	return sql r.db {
		select from models.Adjustment where employee_id == emp_id && organization_id == org_id
	} or { [] }
}

pub fn (mut r Repository) create_adjustment(adj models.Adjustment) !int {
	inserted_id := sql r.db {
		insert adj into models.Adjustment
	}!
	return inserted_id
}

pub fn (mut r Repository) update_adjustment(adj models.Adjustment, org_id int) ! {
	sql r.db {
		update models.Adjustment set amount = adj.amount, description = adj.description where id == adj.id && organization_id == org_id
	}!
}

pub fn (mut r Repository) delete_adjustment(adj_id int, org_id int) ! {
	sql r.db {
		delete from models.Adjustment where id == adj_id && organization_id == org_id
	}!
}

pub fn (r &Repository) get_adjustment_by_id(adj_id int, org_id int) ?models.Adjustment {
	result := sql r.db {
		select from models.Adjustment where id == adj_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}