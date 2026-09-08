module repository

import models

// ==================== TAX BRACKETS (Pilier 2.2) ====================

pub fn (r &Repository) get_brackets(org_id int) []models.TaxBracket {
	return sql r.db {
		select from models.TaxBracket where organization_id == org_id
	} or { [] }
}

pub fn (r &Repository) get_bracket_by_id(bracket_id int, org_id int) ?models.TaxBracket {
	result := sql r.db {
		select from models.TaxBracket where id == bracket_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_bracket(bracket models.TaxBracket) !int {
	inserted_id := sql r.db {
		insert bracket into models.TaxBracket
	}!
	return inserted_id
}

pub fn (mut r Repository) update_bracket(bracket models.TaxBracket, org_id int) ! {
	sql r.db {
		update models.TaxBracket set component_code = bracket.component_code,
		lower_bound = bracket.lower_bound, upper_bound = bracket.upper_bound, rate = bracket.rate,
		flat = bracket.flat, effective_from = bracket.effective_from, is_active = bracket.is_active
		where id == bracket.id && organization_id == org_id
	}!
}