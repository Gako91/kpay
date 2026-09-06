module repository

import models

// ==================== EMPLOYEES ====================

pub fn (r &Repository) get_all_employees(org_id int) []models.Employee {
	return sql r.db {
		select from models.Employee where organization_id == org_id && is_active == true
	} or { [] }
}

// get_employees_paginated retourne une page d'employés actifs (offset/limit) avec le total.
// page et limit sont 1-indexés ; limit est borné à 100.
pub fn (r &Repository) get_employees_paginated(page int, page_size int, org_id int) ([]models.Employee, int) {
	offset := (page - 1) * page_size
	employees := sql r.db {
		select from models.Employee where organization_id == org_id && is_active == true order by id asc limit page_size offset offset
	} or { [] }
	total := sql r.db {
		select count from models.Employee where organization_id == org_id && is_active == true
	} or { 0 }
	return employees, total
}

pub fn (r &Repository) get_employee_by_id(emp_id int, org_id int) ?models.Employee {
	result := sql r.db {
		select from models.Employee where id == emp_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_employee_by_email(emp_email string, org_id int) bool {
	result := sql r.db {
		select from models.Employee where email == emp_email && organization_id == org_id limit 1
	} or { return false }
	return result.len > 0
}

pub fn (mut r Repository) create_employee(emp models.Employee) !int {
	emp_exists := sql r.db {
		select from models.Employee where email == emp.email && organization_id == emp.organization_id
	} or { [] }
	if emp_exists.len > 0 {
		return error("L'employé avec l'email '${emp.email}' existe déjà")
	}
	inserted_id := sql r.db {
		insert emp into models.Employee
	}!
	return inserted_id
}

pub fn (mut r Repository) update_employee(emp models.Employee) ! {
	sql r.db {
		update models.Employee set first_name = emp.first_name, last_name = emp.last_name,
		email = emp.email, iban = emp.iban, bic = emp.bic, is_active = emp.is_active where id == emp.id && organization_id == emp.organization_id
	}!
}

pub fn (mut r Repository) delete_employee(emp_id int, org_id int) ! {
	sql r.db {
		update models.Employee set is_active = false where id == emp_id && organization_id == org_id
	}!
}