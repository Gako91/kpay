module api

import veb
import dto
import json2

// POST /me/profile - L'employé connecté demande une modification de son profil (validation RH requise)
@['/me/profile'; post]
pub fn (mut app App) request_profile_change(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}

	body := ctx.req.data
	input := json2.decode[dto.ProfileChangeInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	req := app.profile_svc.request_change(emp, input.field.trim_space().to_lower(), input.value, ctx.user_org) or {
		if err.msg().contains('déjà en attente') {
			ctx.res.set_status(.conflict)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'profile.change.request', 'profile_change_request', req.id, "Champ '${req.field_name}' demandé par employé ${emp.id}")
	ctx.res.set_status(.created)
	return ctx.json(req)
}

// GET /me/profile-requests - Historique des demandes de modification de l'employé connecté
@['/me/profile-requests']
pub fn (app &App) get_my_profile_requests(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(app.repo.get_profile_change_requests_by_employee(emp.id, ctx.user_org))
}

// GET /profile-changes - Liste des demandes de modification (RH), filtrable par statut
@['/profile-changes']
pub fn (app &App) get_profile_changes(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	status := ctx.query['status']
	return ctx.json(app.profile_svc.list_requests(ctx.user_org, status))
}

// POST /profile-changes/:id/approve - Valider une demande (RH) : applique la modification
@['/profile-changes/:id/approve'; post]
pub fn (mut app App) approve_profile_change(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'profile_change_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	req := app.profile_svc.approve(id, ctx.user_sub, ctx.user_org) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'profile.change.approve', 'profile_change_request', id, "Champ '${req.field_name}' approuvé par ${ctx.user_sub}")
	return ctx.json(dto.ApiResponse{
		success: true
		data: req.field_name
		message: "Modification '${req.field_name}' validée et appliquée au dossier employé"
	})
}

// POST /profile-changes/:id/reject - Refuser une demande (RH), motif obligatoire
@['/profile-changes/:id/reject'; post]
pub fn (mut app App) reject_profile_change(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'profile_change_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	body := ctx.req.data
	input := json2.decode[dto.ProfileRejectInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	req := app.profile_svc.reject(id, ctx.user_sub, input.reason, ctx.user_org) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
		} else {
			ctx.res.set_status(.bad_request)
		}
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'profile.change.reject', 'profile_change_request', id, "Champ '${req.field_name}' refusé par ${ctx.user_sub}")
	return ctx.json(dto.ApiResponse{
		success: true
		data: req.field_name
		message: "Modification '${req.field_name}' refusée — aucun changement appliqué"
	})
}