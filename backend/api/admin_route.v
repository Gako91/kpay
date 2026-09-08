module api

import veb
import dto
import json2
import models

// POST /admin/organizations - Créer une organisation + son admin dédié
// Réservé à l'administrateur plateforme (org 1).
@['/admin/organizations'; post]
pub fn (mut app App) create_organization(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin']) || ctx.user_org != 1 {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — réservé à l\'administrateur plateforme'))
	}
	body := ctx.req.data
	req := json2.decode[dto.CreateOrganizationRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	res := app.admin_svc.create_organization_with_admin(req) or {
		if err.msg().contains('existe déjà') || err.msg().contains('déjà pris') {
			ctx.res.set_status(.conflict)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
	}
	app.audit_action(mut ctx, 'admin.organization.create', 'organization', res.org_id,
		"Organisation '${res.name}' créée avec admin '${res.admin_username}'")
	ctx.res.set_status(.created)
	return ctx.json(res)
}

// GET /admin/organizations - Liste des organisations (plateforme, org 1)
@['/admin/organizations'; get]
pub fn (app &App) list_organizations(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin']) || ctx.user_org != 1 {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — réservé à l\'administrateur plateforme'))
	}
	orgs := app.admin_svc.get_all_organizations()
	return ctx.json(orgs)
}

// GET /admin/org-settings - Paramètres de congés de l'organisation courante
// (carence maladie + délai de déclaration). Accès : admin / gestionnaire RH (payroll_officer).
// Retourne toujours un objet complet : les colonnes ont des valeurs par défaut en base.
@['/admin/org-settings'; get]
pub fn (app &App) get_org_settings(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	org := app.repo.get_organization_by_id(ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Organisation introuvable'))
	}
	return ctx.json(org)
}

// PUT /admin/org-settings - Mise à jour des règles de carence & délai de déclaration
// de l'organisation courante (scoped par tenant). Accès : admin / gestionnaire RH.
@['/admin/org-settings'; put]
pub fn (mut app App) update_org_settings(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	input := json2.decode[dto.OrgLeaveSettingsInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	input.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	app.repo.get_organization_by_id(ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Organisation introuvable'))
	}
	app.repo.update_leave_settings(ctx.user_org, input.carence_days, input.deadline_days) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur mise à jour des paramètres congés: ${err}'))
	}

	app.audit_action(mut ctx, 'admin.org_settings', 'organization', ctx.user_org,
		"Paramètres congés mis à jour (carence: ${input.carence_days}j, délai déclaration: ${input.deadline_days}j)")

	return ctx.json(dto.ApiResponse{
		success: true
		data: '${ctx.user_org}'
		message: 'Paramètres congés mis à jour avec succès'
	})
}