module repository

import time
import models

// ==================== RBAC — PERMISSIONS ====================

// get_all_permissions retourne le catalogue complet des permissions.
pub fn (r &Repository) get_all_permissions() []models.Permission {
	return sql r.db {
		select from models.Permission
	} or { [] }
}

// get_role_permissions retourne les codes de permission d'un rôle.
// Le rôle admin possède toutes les permissions de façon implicite (côté serveur).
pub fn (r &Repository) get_role_permissions(role string) []string {
	rows := sql r.db {
		select from models.RolePermission where role == role
	} or { return [] }
	mut codes := []string{}
	for rp in rows {
		codes << rp.permission_code
	}
	return codes
}

// get_role_permission_map retourne un mapping rôle → []codes pour tous les rôles.
pub fn (r &Repository) get_role_permission_map() map[string][]string {
	mut out := map[string][]string{}
	for role in models.default_roles {
		if role == 'admin' {
			continue // implicite
		}
		out[role] = r.get_role_permissions(role)
	}
	return out
}

// set_role_permissions remplace l'ensemble des permissions d'un rôle (transaction).
// Les codes inconnus sont ignorés (contrainte FK). Gestion du rôle admin interdite.
pub fn (mut r Repository) set_role_permissions(role string, codes []string) ! {
	if role == 'admin' {
		return error('Le rôle admin possède toutes les permissions de façon implicite')
	}
	r.begin_transaction()!
	mut valid := []string{}
	all_perms := r.get_all_permissions()
	for c in codes {
		mut found := false
		for p in all_perms {
			if p.code == c {
				found = true
				break
			}
		}
		if found {
			valid << c
		}
	}
	r.db.exec_param_many('DELETE FROM role_permission WHERE role = \$1', [role]) or {
		r.rollback()
		return error('Échec de la mise à jour des permissions: ${err}')
	}
	for c in valid {
		r.db.exec_param_many('INSERT INTO role_permission (role, permission_code) VALUES (\$1, \$2) ON CONFLICT DO NOTHING', [
			role,
			c,
		]) or {
			r.rollback()
			return error('Échec de l\'insertion des permissions: ${err}')
		}
	}
	r.commit() or {
		r.rollback()
		return error('Échec du commit: ${err}')
	}
}

// ==================== SSO — USER_SSO ====================

// find_user_sso retrouve un lien SSO par fournisseur + sub externe.
pub fn (r &Repository) find_user_sso(provider string, external_sub string) ?models.UserSso {
	rows := sql r.db {
		select from models.UserSso where provider == provider && external_sub == external_sub limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}

// get_user_sso_links liste les liens SSO d'un utilisateur.
pub fn (r &Repository) get_user_sso_links(user_id int) []models.UserSso {
	return sql r.db {
		select from models.UserSso where user_id == user_id
	} or { [] }
}

// save_user_sso enregistre un nouveau lien SSO.
pub fn (mut r Repository) save_user_sso(link models.UserSso) !int {
	return sql r.db {
		insert link into models.UserSso
	}!
}

// delete_user_sso supprime un lien SSO.
pub fn (mut r Repository) delete_user_sso(id int) {
	sql r.db {
		delete from models.UserSso where id == id
	} or {}
}

// ==================== SSO — SSO_STATE (PKCE) ====================

// save_sso_state enregistre un état PKCE OIDC (expire après `ttl_secs` secondes).
pub fn (mut r Repository) save_sso_state(state string, code_verifier string, ttl_secs int) ! {
	st := models.SsoState{
		state: state
		code_verifier: code_verifier
		expires_at: time.now().add_seconds(ttl_secs)
	}
	sql r.db {
		insert st into models.SsoState
	} or {
		return error('Impossible d\'enregistrer l\'état SSO: ${err}')
	}
}

// get_sso_state retourne (et consomme immédiatement) un état PKCE non expiré.
pub fn (mut r Repository) get_sso_state(state string) ?models.SsoState {
	rows := sql r.db {
		select from models.SsoState where state == state limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	st := rows[0]
	sql r.db {
		delete from models.SsoState where state == state
	} or {}
	exp := st.expires_at or { return none }
	if exp.unix() < time.now().unix() {
		return none
	}
	return st
}

// delete_expired_sso_states purge les états expirés (ménage best effort).
pub fn (mut r Repository) delete_expired_sso_states() {
	r.db.exec("DELETE FROM sso_state WHERE expires_at < NOW();") or {}
}