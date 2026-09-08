module repository

import models

// get_leave_balance retourne le solde annuel d'un employé pour un type donné.
pub fn (r &Repository) get_leave_balance(employee_id int, year int, leave_type string, org_id int) ?models.LeaveBalance {
	result := sql r.db {
		select from models.LeaveBalance where employee_id == employee_id && year == year && leave_type == leave_type && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// get_leave_balances retourne tous les soldes annuels d'un employé.
pub fn (r &Repository) get_leave_balances(employee_id int, year int, org_id int) []models.LeaveBalance {
	return sql r.db {
		select from models.LeaveBalance where employee_id == employee_id && year == year && organization_id == org_id order by leave_type asc
	} or { [] }
}

// create_leave_balance insère une ligne de solde.
pub fn (mut r Repository) create_leave_balance(b models.LeaveBalance) !int {
	return sql r.db {
		insert b into models.LeaveBalance
	}!
}

// add_used_leave_days débite le solde utilisé lors de la validation RH.
pub fn (mut r Repository) add_used_leave_days(id int, org_id int, days f32) ! {
	r.db.exec_param_many('UPDATE leave_balance SET used_days = used_days + \$3 WHERE id = \$1 AND organization_id = \$2', [
		id.str(),
		org_id.str(),
		days.str(),
	]) or {
		return error("Échec de la mise à jour du solde: ${err}")
	}
}