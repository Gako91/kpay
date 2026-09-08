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

// update_leave_settings met à jour les règles de carence & délai de déclaration d'une organisation.
pub fn (mut r Repository) update_leave_settings(org_id int, carence_days int, deadline_days int) ! {
	r.db.exec_param_many('UPDATE organization SET leave_carence_days = \$2, leave_declaration_deadline_days = \$3 WHERE id = \$1;', [
		org_id.str(),
		carence_days.str(),
		deadline_days.str(),
	]) or {
		return error("Échec de la mise à jour des paramètres congés: ${err}")
	}
}