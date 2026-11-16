module api

import veb
import os
import dto
import services

// recalculate_payslip POST /payslips/:id/recalculate — recalcule un bulletin en
// brouillon (contrat actif, ajustements du mois, règles en vigueur à la période)
// et remplace son détail figé. Le PDF en cache est supprimé.
@['/payslips/:id/recalculate'; post]
pub fn (mut app App) recalculate_payslip(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) || !ctx.has_permission('payroll.run') {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — permission payroll.run requise'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	mut payroll_service := services.new_payroll_service(mut app.repo)
	updated, old_net := payroll_service.recalculate_payslip(ctx.user_org, id) or {
		msg := err.msg()
		if msg.starts_with('Bulletin') && msg.contains('introuvable') {
			ctx.res.set_status(.not_found)
		} else {
			ctx.res.set_status(.unprocessable_entity)
		}
		return ctx.json(dto.error_response(msg))
	}
	// Invalidation du PDF : objet MinIO et cache disque (régénérés à la prochaine demande)
	object_name := 'org_${ctx.user_org}/bulletin_${id}.pdf'
	app.storage_svc.delete_file(object_name) or {
		services.log_warn('Bulletin ${id} recalculé mais PDF MinIO non supprimé : ${err}')
	}
	os.rm('storage/payslips/${object_name}') or {}
	app.audit_action(mut ctx, 'payslip.recalculate', 'payslip', id, 'Net ${old_net} → ${updated.net_amount}')
	return ctx.json(updated)
}

// payslip_lines GET /payslips/:id/lines — détail figé des retenues d'un bulletin.
@['/payslips/:id/lines']
pub fn (app &App) payslip_lines(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.get_payslip_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Bulletin non trouvé'))
	}
	return ctx.json(app.repo.get_payslip_lines(id, ctx.user_org))
}
