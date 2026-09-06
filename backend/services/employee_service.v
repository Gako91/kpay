module services

import models
import repository

// Service de gestion des employés
pub struct EmployeeService {
mut:
	repo repository.Repository
}

pub fn new_employee_service(mut repo repository.Repository) EmployeeService {
	return EmployeeService{
		repo: repo
	}
}

pub fn (s &EmployeeService) get_all(org_id int) []models.Employee {
	return s.repo.get_all_employees(org_id)
}

pub fn (s &EmployeeService) get_by_id(id int, org_id int) ?models.Employee {
	return s.repo.get_employee_by_id(id, org_id)
}

pub fn (mut s EmployeeService) create(emp models.Employee) !int {
	inserted_id := s.repo.create_employee(emp)!
	log_info('Employé créé: ${emp.first_name} ${emp.last_name}')
	return inserted_id
}

pub fn (mut s EmployeeService) update(emp models.Employee) ! {
	s.repo.update_employee(emp)!
	log_info('Employé mis à jour: ID ${emp.id}')
}

pub fn (mut s EmployeeService) deactivate(id int, org_id int) ! {
	s.repo.delete_employee(id, org_id)!
	log_info('Employé désactivé: ID ${id}')
}