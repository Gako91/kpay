module api

import models
import json2
import veb
import dto
import time

// GET /employees?page=1&limit=50 - Liste paginée des employés
@['/employees']
pub fn (app &App) get_employees(mut ctx Context) veb.Result {
	page := if ctx.query['page'].len > 0 { ctx.query['page'].int() } else { 1 }
	if page < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'page' doit être >= 1"))
	}
	page_size := if ctx.query['limit'].len > 0 { ctx.query['limit'].int() } else { 50 }
	if page_size < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'limit' doit être >= 1"))
	}
	employees, total := app.repo.get_employees_paginated(page, page_size)
	items := dto.PageResponse[models.Employee]{
		data: employees
		page: page
		page_size: page_size
		total: total
		total_pages: if page_size > 0 { (total + page_size - 1) / page_size } else { 0 }
	}
	return ctx.json(items)
}

// GET /employees/:id
@['/employees/:id']
pub fn (app &App) get_employee(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	emp := app.employee_svc.get_by_id(id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	return ctx.json(emp)
}

// POST /employees
@['/employees'; post]
pub fn (mut app App) create_employee(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	emp := json2.decode[models.Employee](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	dto.validate_employee(emp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	new_id := app.employee_svc.create(emp) or {
		// Unicité email et autres erreurs remontées par le service
		if err.msg().contains('existe déjà') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}

	ctx.res.set_status(.created)
	app.audit_action(mut ctx, 'employee.create', 'employee', int(new_id), 'Création de ${emp.first_name} ${emp.last_name}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Employé créé' })
}

// GET /contracts/:employee_id
@['/contracts/:employee_id']
pub fn (app &App) get_contract(mut ctx Context, employee_id int) veb.Result {
	dto.validate_id(employee_id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	contract := app.contract_svc.get_active(employee_id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun contrat actif'))
	}
	return ctx.json(contract)
}

// GET /employees/:id/contracts - Historique des contrats d'un employé
@['/employees/:id/contracts']
pub fn (app &App) get_employee_contracts(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.employee_svc.get_by_id(id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	contracts := app.contract_svc.get_by_employee(id)
	return ctx.json(contracts)
}

// PUT /employees/:id - Mettre à jour un employé
@['/employees/:id'; put]
pub fn (mut app App) update_employee(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	body := ctx.req.data
	decoded := json2.decode[models.Employee](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	emp := models.Employee{
		...decoded
		id: id // Forcer l'ID depuis l'URL
	}

	dto.validate_employee(emp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	// Vérifier que l'employé existe
	app.employee_svc.get_by_id(id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}

	app.employee_svc.update(emp) or {
		if err.msg().contains('existe déjà') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'employee.update', 'employee', id, 'Mise à jour de ${emp.first_name} ${emp.last_name}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Employé mis à jour' })
}

// DELETE /employees/:id - Désactiver un employé (soft delete)
@['/employees/:id'; delete]
pub fn (mut app App) delete_employee(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.employee_svc.get_by_id(id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	app.employee_svc.deactivate(id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors de la désactivation'))
	}
	app.audit_action(mut ctx, 'employee.delete', 'employee', id, 'Employé désactivé')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Employé désactivé' })
}

// POST /contracts - Créer un contrat pour un employé
@['/contracts'; post]
pub fn (mut app App) create_contract(mut ctx Context) veb.Result {
	body := ctx.req.data
	contract := json2.decode[models.Contract](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	dto.validate_contract(contract) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	// Vérifier que l'employé existe
	app.employee_svc.get_by_id(contract.employee_id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé introuvable (id: ${contract.employee_id})'))
	}

	// Forcer start_date à aujourd'hui si non fourni (time.Time{} = zéro invalide pour PostgreSQL)
	effective_start := if contract.start_date.year > 0 {
		contract.start_date
	} else {
		time.now()
	}
	ready := models.Contract{
		...contract
		start_date: effective_start
	}

	new_id := app.contract_svc.create(ready) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}

	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Contrat créé' })
}
