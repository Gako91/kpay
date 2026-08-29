module repository

import models

// ==================== CONTRACTS ====================

pub fn (r &Repository) get_active_contract(emp_id int) ?models.Contract {
	result := sql r.db {
		select from models.Contract where employee_id == emp_id order by id desc limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_contracts_by_employee(emp_id int) []models.Contract {
	return sql r.db {
		select from models.Contract where employee_id == emp_id
	} or { [] }
}

pub fn (mut r Repository) create_contract(contract models.Contract) !int {
	inserted_id := sql r.db {
		insert contract into models.Contract
	}!
	return inserted_id
}
