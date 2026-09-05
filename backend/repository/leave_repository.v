module repository

import models

// create_leave_request enregistre une nouvelle demande de congé.
pub fn (mut r Repository) create_leave_request(req models.LeaveRequest) !models.LeaveRequest {
	mut entry := req
	entry = models.LeaveRequest{
		...entry
		status: 'en_attente'
	}
	inserted_id := sql r.db {
		insert entry into models.LeaveRequest
	}!
	return models.LeaveRequest{
		...entry
		id: inserted_id
	}
}

// get_leave_requests_by_employee récupère toutes les demandes d'un employé.
pub fn (mut r Repository) get_leave_requests_by_employee(employee_id int) ![]models.LeaveRequest {
	return sql r.db {
		select from models.LeaveRequest where employee_id == employee_id
	}!
}

// get_all_leave_requests récupère toutes les demandes de congé.
pub fn (mut r Repository) get_all_leave_requests() ![]models.LeaveRequest {
	return sql r.db {
		select from models.LeaveRequest
	}!
}

// update_leave_status met à jour le statut d'une demande de congé.
pub fn (mut r Repository) update_leave_status(id int, status string, approved_by string) ! {
	sql r.db {
		update models.LeaveRequest set status = status, approved_by = approved_by where id == id
	}!
}
