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

// ensure_platform_organization garantit l'existence de l'organisation plateforme
// (id 1, idempotent) puis recale la séquence d'ids sur MAX(id). Sans ce recalage,
// l'id explicite 1 laisse la séquence en retard et la première organisation créée
// via /admin/organizations échoue sur "duplicate key organization_pkey".
// Retourne true si l'organisation vient d'être créée.
pub fn (mut r Repository) ensure_platform_organization(name string, tax_id string, currency string) !bool {
	mut tx := r.begin()!
	rows := tx.exec_param_many('INSERT INTO organization (id, name, tax_id, currency, created_at) VALUES (1, \$1, \$2, \$3, NOW()) ON CONFLICT (id) DO NOTHING RETURNING id', [
		name,
		tax_id,
		currency,
	]) or {
		tx.rollback() or {}
		return error("Création de l'organisation plateforme impossible: ${err}")
	}
	tx.exec("SELECT setval(pg_get_serial_sequence('organization', 'id'), (SELECT MAX(id) FROM organization))") or {
		tx.rollback() or {}
		return error('Recalage de la séquence organization impossible: ${err}')
	}
	tx.commit()!
	return rows.len > 0
}

// create_organization_with_admin crée une organisation et son compte admin de façon
// atomique (même transaction) : pas d'organisation orpheline si le compte échoue.
// Retourne (org_id, user_id).
pub fn (mut r Repository) create_organization_with_admin(org models.Organization, admin models.User) !(int, int) {
	existing := sql r.db {
		select from models.User where username == admin.username
	} or { [] }
	if existing.len > 0 {
		return error("Le nom d'utilisateur '${admin.username}' existe déjà")
	}

	mut tx := r.begin()!
	org_id := sql tx {
		insert org into models.Organization
	} or {
		tx.rollback() or {}
		return error("Échec de la création de l'organisation: ${err}")
	}
	user := models.User{
		...admin
		organization_id: org_id
	}
	user_id := sql tx {
		insert user into models.User
	} or {
		tx.rollback() or {}
		return error("Échec de la création de l'admin: ${err}")
	}
	tx.commit()!
	return org_id, user_id
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