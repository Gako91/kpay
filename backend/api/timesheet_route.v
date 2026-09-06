module api

import models
import json2
import veb
import dto
import time

// GET /employees/:id/timesheets?month=&year= - Récupérer le timesheet d'un employé pour une période
@['/employees/:id/timesheets']
pub fn (app &App) get_timesheet(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	month := if ctx.query['month'].len > 0 { ctx.query['month'].int() } else { time.now().month }
	year := if ctx.query['year'].len > 0 { ctx.query['year'].int() } else { time.now().year }

	ts := app.repo.get_timesheet(id, month, year, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun timesheet pour cette période'))
	}
	return ctx.json(ts)
}

// POST /timesheets - Créer ou mettre à jour un timesheet
@['/timesheets'; post]
pub fn (mut app App) create_timesheet(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.Timesheet](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	ts := models.Timesheet{
		...decoded
		organization_id: ctx.user_org
	}
	dto.validate_timesheet(ts) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	// Vérifier que l'employé existe
	app.employee_svc.get_by_id(ts.employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé introuvable'))
	}
	new_id := app.repo.create_timesheet(ts) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Timesheet enregistré' })
}

// PUT /timesheets/:id - Mettre à jour un timesheet
@['/timesheets/:id'; put]
pub fn (mut app App) update_timesheet(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'timesheet_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	body := ctx.req.data
	decoded := json2.decode[models.Timesheet](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	ts := models.Timesheet{
		...decoded
		id: id
		organization_id: ctx.user_org
	}
	dto.validate_timesheet(ts) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.update_timesheet(ts, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Timesheet mis à jour' })
}

// DELETE /timesheets/:id - Supprimer un timesheet
@['/timesheets/:id'; delete]
pub fn (mut app App) delete_timesheet(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'timesheet_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.delete_timesheet(id, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Timesheet supprimé' })
}

// ==================== ADJUSTMENTS ====================

// GET /employees/:id/adjustments?month=&year= - Récupérer les primes/retenues d'un employé
@['/employees/:id/adjustments']
pub fn (app &App) get_adjustments(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	month := if ctx.query['month'].len > 0 { ctx.query['month'].int() } else { 0 }
	year := if ctx.query['year'].len > 0 { ctx.query['year'].int() } else { 0 }

	adjustments := if month > 0 && year > 0 {
		app.repo.get_adjustments_for_period(id, month, year, ctx.user_org)
	} else {
		app.repo.get_adjustments(id, ctx.user_org)
	}
	return ctx.json(adjustments)
}

// POST /adjustments - Créer un ajustement (prime/retenue)
@['/adjustments'; post]
pub fn (mut app App) create_adjustment(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.Adjustment](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	date_val := if decoded.date.year == 0 { time.now() } else { decoded.date }
	adj := models.Adjustment{
		...decoded
		organization_id: ctx.user_org
		date: date_val
	}
	dto.validate_adjustment(adj) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.employee_svc.get_by_id(adj.employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé introuvable'))
	}
	new_id := app.repo.create_adjustment(adj) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Ajustement créé' })
}

// PUT /adjustments/:id - Mettre à jour un ajustement
@['/adjustments/:id'; put]
pub fn (mut app App) update_adjustment(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'adjustment_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	body := ctx.req.data
	decoded := json2.decode[models.Adjustment](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	date_val := if decoded.date.year == 0 { time.now() } else { decoded.date }
	adj := models.Adjustment{
		...decoded
		id: id
		organization_id: ctx.user_org
		date: date_val
	}
	dto.validate_adjustment(adj) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.update_adjustment(adj, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Ajustement mis à jour' })
}

// DELETE /adjustments/:id - Supprimer un ajustement
@['/adjustments/:id'; delete]
pub fn (mut app App) delete_adjustment(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'adjustment_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.delete_adjustment(id, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Ajustement supprimé' })
}