module repository

import models

// ==================== ORGANIZATIONS (TENANTS) ====================

pub fn (r &Repository) get_all_organizations() []models.Organization {
	return sql r.db {
		select from models.Organization order by id asc
	} or { [] }
}

pub fn (r &Repository) get_organization_by_id(org_id int) ?models.Organization {
	result := sql r.db {
		select from models.Organization where id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_organization_by_name(name string) ?models.Organization {
	result := sql r.db {
		select from models.Organization where name == name limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_organization(org models.Organization) !int {
	inserted_id := sql r.db {
		insert org into models.Organization
	}!
	return inserted_id
}