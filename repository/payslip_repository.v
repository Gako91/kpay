module repository

import models

// ==================== PAYSLIPS ====================
pub fn (r &Repository) get_payslips_by_employee(emp_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where employee_id == emp_id order by id desc
	} or { [] }
}

pub fn (r &Repository) get_payslip_by_id(payslip_id int) ?models.Payslip {
	result := sql r.db {
		select from models.Payslip where id == payslip_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_payslip(payslip models.Payslip) !int {
	inserted_id := sql r.db {
		insert payslip into models.Payslip
	}!
	return inserted_id
}

pub fn (mut r Repository) mark_payslip_paid(payslip_id int) ! {
	sql r.db {
		update models.Payslip set is_paid = true where id == payslip_id
	}!
}

// update_payslip_pdf_path enregistre le chemin du PDF généré sur le bulletin.
pub fn (mut r Repository) update_payslip_pdf_path(payslip_id int, path string) ! {
	sql r.db {
		update models.Payslip set pdf_path = path where id == payslip_id
	}!
}
