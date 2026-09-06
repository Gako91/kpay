module api

import veb
import models
import dto

// current_employee résout le dossier employé lié au compte authentifié.
// /me est réservé aux sessions JWT (user_sub = username des claims).
fn (app &App) current_employee(ctx Context) !models.Employee {
	if ctx.user_sub.len == 0 {
		return error('Accès ESS non disponible sur les clés API')
	}
	user := app.repo.get_user_by_username(ctx.user_sub) or { return error('Compte introuvable') }
	return app.repo.get_employee_by_user_id(user.id, ctx.user_org) or {
		return error('Aucun dossier employé lié à ce compte')
	}
}

// GET /me/payslips - Bulletins de l'employé connecté (self-service), filtrable par période
@['/me/payslips']
pub fn (app &App) get_my_payslips(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	month := if ctx.query['month'].len > 0 {
		ctx.query['month'].int()
	} else {
		0
	}
	year := if ctx.query['year'].len > 0 {
		ctx.query['year'].int()
	} else {
		0
	}

	payslips := if month > 0 && year > 0 {
		app.repo.get_payslips_by_employee_period(emp.id, month, year, ctx.user_org)
	} else {
		app.repo.get_payslips_by_employee(emp.id, ctx.user_org)
	}
	return ctx.json(payslips)
}

// GET /me/payslips/:id/pdf - Téléchargement sécurisé du bulletin de l'employé connecté
@['/me/payslips/:id/pdf']
pub fn (mut app App) get_my_payslip_pdf(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}

	// Vérification du propriétaire : le bulletin doit appartenir à l'employé lié ET à l'org
	app.repo.get_payslip_by_employee_period_id(emp.id, id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Bulletin non trouvé'))
	}

	app.audit_action(mut ctx, 'pay.self.payslip.download', 'payslip', id, "Téléchargement PDF via /me (employé ${emp.id})")
	return app.render_payslip_pdf(mut ctx, id)
}

// current_employee_info GET /me - Profil de l'employé connecté (ESS)
@['/me']
pub fn (app &App) get_me(mut ctx Context) veb.Result {
	emp := app.current_employee(ctx) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(emp)
}