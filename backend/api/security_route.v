module api

import veb
import dto
import json2
import models
import common

// ==================== AUTH — DEUXIÈME ÉTAPE MFA ====================

// auth_login_mfa POST /auth/login/mfa - Échange du challenge MFA contre un JWT final
@['/auth/login/mfa'; post]
pub fn (mut app App) auth_login_mfa(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.MfaLoginRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	if req.mfa_token.len == 0 || req.code.len == 0 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('mfa_token et code requis'))
	}
	res := app.auth_svc.login_mfa(req.mfa_token, req.code) or {
		app.audit_action(mut ctx, 'auth.login.mfa', 'user', 0, 'Code MFA invalide: ${err}')
		ctx.res.set_status(.unauthorized)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'auth.login.mfa', 'user', 0, 'Connexion MFA réussie pour ${res.sub}')
	return ctx.json(res)
}

// ==================== MFA TOTP (Pilier 3) ====================

// mfa_enroll POST /mfa/enroll - Génère un secret TOTP + codes de secours (MFA pas encore actif)
@['/mfa/enroll'; post]
pub fn (mut app App) mfa_enroll(mut ctx Context) veb.Result {
	res := app.auth_svc.mfa_enroll(ctx.user_sub) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'mfa.enroll', 'user', 0, "Enrôlement MFA démarré pour ${ctx.user_sub}")
	return ctx.json(res)
}

// mfa_verify POST /mfa/verify - Valide le premier code TOTP et active le MFA
@['/mfa/verify'; post]
pub fn (mut app App) mfa_verify(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.MfaEnrollRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	app.auth_svc.mfa_verify(ctx.user_sub, req.code) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'mfa.verify', 'user', 0, "MFA activé pour ${ctx.user_sub}")
	return ctx.json(dto.ApiResponse{ success: true, data: 'ok', message: 'MFA activé' })
}

// mfa_disable POST /mfa/disable - Désactive le MFA (mot de passe requis)
@['/mfa/disable'; post]
pub fn (mut app App) mfa_disable(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.MfaDisableRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	app.auth_svc.mfa_disable(ctx.user_sub, req.password) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'mfa.disable', 'user', 0, "MFA désactivé pour ${ctx.user_sub}")
	return ctx.json(dto.ApiResponse{ success: true, data: 'ok', message: 'MFA désactivé' })
}

// mfa_status GET /mfa/status - État MFA du compte courant
@['/mfa/status'; get]
pub fn (app &App) mfa_status(mut ctx Context) veb.Result {
	res := app.auth_svc.mfa_status(ctx.user_sub) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(res)
}

// ==================== SSO OIDC (Pilier 3) ====================

// sso_config GET /auth/sso/config - Configuration OIDC exposée au frontend (sans secret)
@['/auth/sso/config'; get]
pub fn (app &App) sso_config(mut ctx Context) veb.Result {
	return ctx.json(app.auth_svc.sso_config())
}

// sso_authorize GET /auth/sso/authorize - Redirige vers le fournisseur (Authorization Code + PKCE)
@['/auth/sso/authorize'; get]
pub fn (mut app App) sso_authorize(mut ctx Context) veb.Result {
	if !app.auth_svc.sso_enabled() {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('SSO non configuré'))
	}
	url, _ := app.auth_svc.sso_authorize_url() or {
		ctx.res.set_status(.bad_gateway)
		return ctx.json(dto.error_response(err.msg()))
	}
	ctx.res.set_status(.found)
	ctx.res.header.set_custom('Location', url) or {}
	return ctx.text('')
}

// sso_callback GET /auth/sso/callback?code=&state= - Échange du code contre un JWT KPay
@['/auth/sso/callback'; get]
pub fn (mut app App) sso_callback(mut ctx Context) veb.Result {
	code := ctx.query['code']
	state := ctx.query['state']
	if app.auth_svc.sso_enabled() {
		res := app.auth_svc.sso_exchange_code(code, state) or {
			app.audit_action(mut ctx, 'auth.sso', 'user', 0, "Échec SSO: ${err}")
			// Redirection vers le frontend avec erreur encodée
			note := common.url_encode('Connexion SSO refusée : ' + err.msg())
			ctx.res.set_status(.found)
			ctx.res.header.set_custom('Location', '/?sso_error=${note}') or {}
			return ctx.text('')
		}
		app.audit_action(mut ctx, 'auth.sso', 'user', 0, "Connexion SSO réussie pour ${res.sub}")
		// Le JWT est remis au frontend via le fragment (page servie par le frontend).
		ctx.res.set_status(.found)
		ctx.res.header.set_custom('Location', '/login#sso=${res.token}&sub=${common.url_encode(res.sub)}&role=${res.role}&org=${res.org}') or {}
		return ctx.text('')
	}
	ctx.res.set_status(.bad_request)
	return ctx.json(dto.error_response('SSO non configuré'))
}

// sso disconnect POST /me/sso/:id - Détache un fournisseur SSO du compte courant
@['/me/sso/:id'; delete]
pub fn (mut app App) me_sso_delete(mut ctx Context, id int) veb.Result {
	user := app.repo.get_user_by_username(ctx.user_sub) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Compte introuvable'))
	}
	links := app.repo.get_user_sso_links(user.id)
	for link in links {
		if link.id == id {
			app.repo.delete_user_sso(id)
			app.audit_action(mut ctx, 'sso.unlink', 'user', id, "Fournisseur SSO détaché (${link.provider})")
			return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Lien SSO supprimé' })
		}
	}
	ctx.res.set_status(.not_found)
	return ctx.json(dto.error_response('Lien SSO introuvable'))
}

// ==================== RBAC ADMIN (Pilier 3) ====================

// list_permissions GET /admin/permissions - Catalogue des permissions (role.manage)
@['/admin/permissions'; get]
pub fn (app &App) list_permissions(mut ctx Context) veb.Result {
	if !ctx.has_permission('role.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: role.manage'))
	}
	return ctx.json(app.repo.get_all_permissions())
}

// list_roles GET /admin/roles - Rôles avec leurs permissions (role.manage)
@['/admin/roles'; get]
pub fn (app &App) list_roles(mut ctx Context) veb.Result {
	if !ctx.has_permission('role.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: role.manage'))
	}
	pcodes := app.repo.get_role_permission_map()
	all := app.repo.get_all_permissions()
	mut all_codes := []string{}
	for p in all {
		all_codes << p.code
	}
	mut roles := []dto.RoleWithPermissions{}
	for role in models.default_roles {
		roles << dto.RoleWithPermissions{
			role: role
			permissions: if role == 'admin' { all_codes } else { pcodes[role] }
			builtin: true
		}
	}
	return ctx.json(roles)
}

// update_role_permissions PUT /admin/roles/:role/permissions - Remplace les permissions d'un rôle
@['/admin/roles/:role/permissions'; put]
pub fn (mut app App) update_role_permissions(mut ctx Context, role string) veb.Result {
	if !ctx.has_permission('role.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: role.manage'))
	}
	if role != 'admin' && !models.default_roles.contains(role) {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Rôle inconnu'))
	}
	body := ctx.req.data
	input := json2.decode[dto.RolePermissionsInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	app.repo.set_role_permissions(role, input.permissions) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'rbac.role.update', 'role', 0, "Permissions du rôle '${role}' mises à jour (${input.permissions.len} codes)")
	return ctx.json(dto.ApiResponse{ success: true, data: role, message: 'Permissions mises à jour' })
}

// update_user_role_route PUT /admin/users/:id - Rôle / statut actif d'un compte (user.manage)
@['/admin/users/:id'; put]
pub fn (mut app App) update_user(mut ctx Context, id int) veb.Result {
	if !ctx.has_permission('user.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: user.manage'))
	}
	body := ctx.req.data
	input := json2.decode[dto.UserUpdateInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	input.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.update_user_role(ctx.user_org, id, input.role, input.is_active) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'rbac.user.update', 'user', id, "Compte ${id} → rôle '${input.role}', actif=${input.is_active}")
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Compte mis à jour' })
}

// create_user_admin POST /admin/users - Créer un compte au sein de l'organisation (user.manage)
@['/admin/users'; post]
pub fn (mut app App) create_user_admin(mut ctx Context) veb.Result {
	if !ctx.has_permission('user.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: user.manage'))
	}
	body := ctx.req.data
	input := json2.decode[dto.UserCreateInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	input.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	user := models.User{
		organization_id: ctx.user_org
		username: input.username
		password_hash: common.hash_password(input.password)
		role: input.role
		email: input.email
		is_active: true
	}
	id := app.repo.create_user(user) or {
		if err.msg().contains('existe déjà') {
			ctx.res.set_status(.conflict)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
	}
	// Auto-lien ESS : associe le dossier employé correspondant (email concordant) dans l'org.
	app.repo.link_employee_by_email(ctx.user_org, id, input.email) or { _ := 0 }
	app.audit_action(mut ctx, 'rbac.user.create', 'user', id, "Compte '${input.username}' créé (rôle ${input.role})")
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Compte créé' })
}

// list_users_admin GET /admin/users - Comptes de l'organisation (user.manage)
@['/admin/users'; get]
pub fn (app &App) list_users_admin(mut ctx Context) veb.Result {
	if !ctx.has_permission('user.manage') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission requise: user.manage'))
	}
	page := if ctx.query['page'].len > 0 { ctx.query['page'].int() } else { 1 }
	page_size := if ctx.query['limit'].len > 0 { ctx.query['limit'].int() } else { 50 }
	if page < 1 || page_size < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('page et limit doivent être >= 1'))
	}
	users, total := app.repo.get_all_org_users_paginated(ctx.user_org, page, page_size)
	return ctx.json(dto.PageResponse[models.User]{
		data: users
		page: page
		page_size: page_size
		total: total
		total_pages: if page_size > 0 { (total + page_size - 1) / page_size } else { 0 }
	})
}

// me_sso_links GET /me/sso - Fournisseurs SSO connectés au compte courant
@['/me/sso'; get]
pub fn (app &App) me_sso_links(mut ctx Context) veb.Result {
	user := app.repo.get_user_by_username(ctx.user_sub) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Compte introuvable'))
	}
	return ctx.json(app.repo.get_user_sso_links(user.id))
}

// require_permission applique une permission granulaire et répond 403 sinon.
fn (app &App) require_permission(mut ctx Context, code string) bool {
	return ctx.has_permission(code)
}