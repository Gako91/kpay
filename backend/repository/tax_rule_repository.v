module repository

import models

// ==================== TAX RULES ====================

pub fn (r &Repository) get_tax_rules(country string, org_id int) []models.TaxRule {
	return sql r.db {
		select from models.TaxRule where country == country && organization_id == org_id
	} or { [] }
}

pub fn (r &Repository) get_all_tax_rules(org_id int) []models.TaxRule {
	return sql r.db {
		select from models.TaxRule where organization_id == org_id
	} or { [] }
}

pub fn (mut r Repository) create_tax_rule(rule models.TaxRule) !int {
	inserted_id := sql r.db {
		insert rule into models.TaxRule
	}!
	return inserted_id
}

pub fn (mut r Repository) update_tax_rule(rule models.TaxRule, org_id int) ! {
	sql r.db {
		update models.TaxRule set name = rule.name, rate = rule.rate, is_employer = rule.is_employer,
		ceiling = rule.ceiling, fixed_amount = rule.fixed_amount, country = rule.country where id == rule.id && organization_id == org_id
	}!
}

pub fn (r &Repository) get_tax_rule_by_id(rule_id int, org_id int) ?models.TaxRule {
	result := sql r.db {
		select from models.TaxRule where id == rule_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}