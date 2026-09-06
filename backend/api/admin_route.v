module api

import veb
import dto
import json2

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