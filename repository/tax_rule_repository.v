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
