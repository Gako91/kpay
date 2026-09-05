module repository

import models

// ==================== TAX RULES ====================

pub fn (r &Repository) get_tax_rules(country string) []models.TaxRule {
	return sql r.db {
		select from models.TaxRule where country == country
	} or { [] }
}

pub fn (r &Repository) get_all_tax_rules() []models.TaxRule {
	return sql r.db {
		select from models.TaxRule
	} or { [] }
}

pub fn (mut r Repository) create_tax_rule(rule models.TaxRule) !int {
	inserted_id := sql r.db {
		insert rule into models.TaxRule
	}!
	return inserted_id
}

pub fn (mut r Repository) update_tax_rule(rule models.TaxRule) ! {
	sql r.db {
		update models.TaxRule set name = rule.name, rate = rule.rate, is_employer = rule.is_employer,
		ceiling = rule.ceiling, fixed_amount = rule.fixed_amount, country = rule.country where id == rule.id
	}!
}

pub fn (r &Repository) get_tax_rule_by_id(rule_id int) ?models.TaxRule {
	result := sql r.db {
		select from models.TaxRule where id == rule_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}
