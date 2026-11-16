module repository

import db.pg
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
	inserted_id := r.insert_id(fn [contract] (mut tx pg.Tx) !int {
		return sql tx {
			insert contract into models.Contract
		}!
	})!
	return inserted_id
}
// get_contract_for_period retourne le contrat en vigueur sur un mois de paie : le
// plus récent dont la date de début précède la fin du mois et qui n'est pas clos
// avant le début du mois. Contrairement à get_active_contract (évalué à la date
// du jour), il permet de générer ou recalculer un mois passé, y compris le dernier
// mois d'un salarié parti depuis.
pub fn (r &Repository) get_contract_for_period(emp_id int, month int, year int, org_id int) ?models.Contract {
	m_start := start_of_month(month, year)
	m_end := end_of_month(month, year)
	for c in r.get_contracts_by_employee(emp_id, org_id) {
		if c.start_date > m_end {
			continue
		}
		if end := c.end_date {
			if end < m_start {
				continue
			}
		}
		return c
	}
	return none
}

// end_contract clôt un contrat à la date donnée (fin de contrat, avenant remplacé).
pub fn (mut r Repository) end_contract(contract_id int, end_date time.Time, org_id int) ! {
	rows := r.db.exec_param_many('UPDATE contract SET end_date = \$3 WHERE id = \$1 AND organization_id = \$2 RETURNING id',
		[contract_id.str(), org_id.str(), end_date.format_ss()])!
	if rows.len == 0 {
		return error('Contrat ${contract_id} introuvable')
	}
}

// get_contract_by_id retourne un contrat de l'organisation.
pub fn (r &Repository) get_contract_by_id(contract_id int, org_id int) ?models.Contract {
	rows := sql r.db {
		select from models.Contract where id == contract_id && organization_id == org_id limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}
