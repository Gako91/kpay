module services

import models
import repository

// Service de gestion des contrats
pub struct ContractService {
mut:
	repo repository.Repository
}

pub fn new_contract_service(mut repo repository.Repository) ContractService {
	return ContractService{
		repo: repo
	}
}

pub fn (s &ContractService) get_active(employee_id int, org_id int) ?models.Contract {
	return s.repo.get_active_contract(employee_id, org_id)
}

pub fn (s &ContractService) get_by_employee(employee_id int, org_id int) []models.Contract {
	return s.repo.get_contracts_by_employee(employee_id, org_id)
}

pub fn (mut s ContractService) create(contract models.Contract) !int {
	inserted_id := s.repo.create_contract(contract)!
	log_info('Contrat créé pour employé ID ${contract.employee_id}')
	return inserted_id
}