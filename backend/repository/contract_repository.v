module repository

import models
import time

// ==================== CONTRACTS ====================

// get_active_contract retourne le contrat actif le plus récent : un contrat est actif
// s'il n'a pas de date de fin, ou si sa date de fin est dans le futur.
pub fn (r &Repository) get_active_contract(emp_id int, org_id int) ?models.Contract {
	contracts := r.get_contracts_by_employee(emp_id, org_id)
	if contracts.len == 0 {
		return none
	}
	// get_contracts_by_employee est trié par id desc (le plus récent en premier)
	for c in contracts {
		if end := c.end_date {
			// Contrat avec date de fin : actif si la date de fin est dans le futur
			if end > time.now() {
				return c
			}
		} else {
			// Contrat sans date de fin (durée indéterminée) : actif
			return c
		}
	}
	return none
}

pub fn (r &Repository) get_contracts_by_employee(emp_id int, org_id int) []models.Contract {
	return sql r.db {
		select from models.Contract where employee_id == emp_id && organization_id == org_id order by id desc
	} or { [] }
}

pub fn (mut r Repository) create_contract(contract models.Contract) !int {
	inserted_id := sql r.db {
		insert contract into models.Contract
	}!
	return inserted_id
}