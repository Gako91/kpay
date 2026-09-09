module repository

import models

// ==================== USERS ====================

pub fn (r &Repository) get_user_by_id(user_id int) ?models.User {
	result := sql r.db {
		select from models.User where id == user_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (r &Repository) get_user_by_username(username string) ?models.User {
	result := sql r.db {
		select from models.User where username == username limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// get_user_by_email retrouve un compte actif par email dans une organisation (SSO strict).
pub fn (r &Repository) get_user_by_email(org_id int, email string) ?models.User {
	rows := sql r.db {
		select from models.User where organization_id == org_id && email == email && is_active == true limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}

// get_user_by_email_any retrouve un compte actif par email, toutes organisations confondues.
// Utilisé au premier lien SSO (le lien provider+sub verrouille ensuite l'utilisateur).
pub fn (r &Repository) get_user_by_email_any(email string) ?models.User {
	rows := sql r.db {
		select from models.User where email == email && is_active == true order by id limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}

pub fn (r &Repository) get_all_users(org_id int) []models.User {
	return sql r.db {
		select from models.User where organization_id == org_id
	} or { [] }
}

pub fn (mut r Repository) create_user(user models.User) !int {
	existing := sql r.db {
		select from models.User where username == user.username
	} or { [] }
	if existing.len > 0 {
		return error("Le nom d'utilisateur '${user.username}' existe déjà")
	}
	inserted_id := sql r.db {
		insert user into models.User
	}!
	return inserted_id
}

// update_user_role met à jour rôle + statut actif d'un compte (RBAC — user.manage).
pub fn (mut r Repository) update_user_role(org_id int, user_id int, role string, is_active bool) ! {
	if role.len == 0 {
		return error('Rôle manquant')
	}
	res := r.db.exec_param_many('UPDATE "user" SET role = \$3, is_active = \$4 WHERE id = \$1 AND organization_id = \$2 RETURNING id', [
		'${user_id}',
		'${org_id}',
		role,
		if is_active { 'true' } else { 'false' },
	]) or {
		return error('Échec de la mise à jour du compte: ${err}')
	}
	if res.len == 0 {
		return error('Compte introuvable dans l\'organisation')
	}
}

// set_mfa_fields enregistre ou met à jour les métadonnées MFA d'un compte.
pub fn (mut r Repository) set_mfa_fields(user_id int, secret string, enabled bool, backup_codes string) ! {
	r.db.exec_param_many("UPDATE \"user\" SET mfa_secret = \$2, mfa_enabled = \$3, mfa_backup_codes = \$4 WHERE id = \$1", [
		'${user_id}',
		secret,
		if enabled { 'true' } else { 'false' },
		backup_codes,
	]) or {
		return error('Échec de la mise à jour MFA: ${err}')
	}
}

// consume_backup_code retire un code de secours utilisé (remplace la liste hashée).
pub fn (mut r Repository) consume_backup_code(user_id int, remaining []string) ! {
	r.db.exec_param_many('UPDATE "user" SET mfa_backup_codes = \$2 WHERE id = \$1', [
		'${user_id}',
		remaining.join(','),
	]) or {
		return error('Échec de la mise à jour des codes de secours: ${err}')
	}
}

// get_all_org_users_paginated liste les comptes d'une organisation (sans hash, paginé).
pub fn (r &Repository) get_all_org_users_paginated(org_id int, page int, page_size int) ([]models.User, int) {
	total_res := r.db.exec_param_many('SELECT COUNT(*) FROM "user" WHERE organization_id = \$1', [
		'${org_id}',
	]) or { users := []models.User{}; return users, 0 }
	total := total_res[0].val(0).int()
	offset := (page - 1) * page_size
	rows_res := r.db.exec_param_many("SELECT id, organization_id, username, role, email, is_active, mfa_enabled FROM \"user\" WHERE organization_id = \$1 ORDER BY id LIMIT \$2 OFFSET \$3", [
		'${org_id}',
		'${page_size}',
		'${offset}',
	]) or { users := []models.User{}; return users, total }
	mut users := []models.User{}
	for row in rows_res {
		users << models.User{
			id: row.val(0).int()
			organization_id: row.val(1).int()
			username: row.val(2).str()
			role: row.val(3).str()
			email: row.val(4).str()
			is_active: row.val(5) == 'true' || row.val(5) == 't' || row.val(5) == '1'
			mfa_enabled: row.val(6) == 'true' || row.val(6) == 't' || row.val(6) == '1'
		}
	}
	return users, total
}

// valid_user_role vérifie qu'un rôle appartient à l'ensemble connu.
pub fn valid_user_role(role string) bool {
	return models.default_roles.contains(role)
}
