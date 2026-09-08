module repository

import models

// ==================== TAX COMPONENTS (Pilier 2.2) ====================

pub fn (r &Repository) get_components(org_id int) []models.TaxComponent {
	return sql r.db {
		select from models.TaxComponent where organization_id == org_id
	} or { [] }
}

pub fn (r &Repository) get_component_by_id(comp_id int, org_id int) ?models.TaxComponent {
	result := sql r.db {
		select from models.TaxComponent where id == comp_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_component(comp models.TaxComponent) !int {
	inserted_id := sql r.db {
		insert comp into models.TaxComponent
	}!
	return inserted_id
}

pub fn (mut r Repository) update_component(comp models.TaxComponent, org_id int) ! {
	sql r.db {
		update models.TaxComponent set code = comp.code, name = comp.name, rate = comp.rate,
		basis_type = comp.basis_type, cap = comp.cap, fixed_amount = comp.fixed_amount,
		share = comp.share, effective_from = comp.effective_from, is_active = comp.is_active,
		country = comp.country where id == comp.id && organization_id == org_id
	}!
}