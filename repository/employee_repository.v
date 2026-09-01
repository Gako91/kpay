module repository

import models

// ==================== EMPLOYEES ====================

pub fn (r &Repository) get_all_employees() []models.Employee {
	return sql r.db {
		select from models.Employee where is_active == true
	} or { [] }
}

pub fn (r &Repository) get_employee_by_id(emp_id int) ?models.Employee {
	result := sql r.db {
		select from models.Employee where id == emp_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_employee_by_email(emp_email string) bool {
	result := sql r.db {
		select from models.Employee where email == emp_email limit 1
	} or { return false }
	return result.len > 0
}

pub fn (mut r Repository) create_employee(emp models.Employee) !int {
	emp_exists := sql r.db {
		select from models.Employee where email == emp.email
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
		email = emp.email, iban = emp.iban, bic = emp.bic, is_active = emp.is_active where id == emp.id
	}!
}

pub fn (mut r Repository) delete_employee(emp_id int) ! {
	sql r.db {
		update models.Employee set is_active = false where id == emp_id
	}!
}
