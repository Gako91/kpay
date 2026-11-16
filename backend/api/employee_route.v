module api

import models
import json2
import veb
import dto
import time

// GET /employees?page=1&limit=50 - Liste paginée des employés
@['/employees']
pub fn (app &App) get_employees(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
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
	employees, total := app.repo.get_employees_paginated(page, page_size, ctx.user_org)
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
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	emp := app.employee_svc.get_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	return ctx.json(emp)
}

// create_employee POST /employees
@['/employees'; post]
pub fn (mut app App) create_employee(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.Employee](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	// json2 ignore les @[default] : un champ absent vaudrait false / 0.
	keys := json_keys(body)
	emp := models.Employee{
		...decoded
		organization_id: ctx.user_org
		is_active: if 'is_active' in keys { decoded.is_active } else { true }
		tax_parts: if 'tax_parts' in keys { decoded.tax_parts } else { f32(1.0) }
		cnps_number: dto.normalize_cnps_number(decoded.cnps_number)
		salary_type: if decoded.salary_type.len > 0 { decoded.salary_type.to_upper() } else { 'M' }
	}

	dto.validate_employee(emp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	// Le manager (N+1) doit exister dans la même organisation
	manager_id := decoded.manager_id or { 0 }
	if manager_id > 0 {
		app.repo.get_employee_by_id(manager_id, ctx.user_org) or {
			ctx.res.set_status(.bad_request)
			return ctx.json(dto.error_response("Manager introuvable dans l'organisation (id: ${manager_id})"))
		}
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
	// Auto-lien ESS : si un compte utilisateur actif possède cet email (même org),
	// on associe le dossier employé pour permettre /me, /me/payslips, etc.
	user := app.repo.get_user_by_email(ctx.user_org, emp.email) or { models.User{} }
	if user.id > 0 {
		app.repo.link_employee_to_user(new_id, user.id, ctx.user_org) or { _ := 0 }
	}

	ctx.res.set_status(.created)
	app.audit_action(mut ctx, 'employee.create', 'employee', int(new_id), 'Création de ${emp.first_name} ${emp.last_name}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Employé créé' })
}

// GET /contracts/:employee_id
@['/contracts/:employee_id']
pub fn (app &App) get_contract(mut ctx Context, employee_id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(employee_id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	contract := app.contract_svc.get_active(employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun contrat actif'))
	}
	return ctx.json(contract)
}

// get_employee_contracts GET /employees/:id/contracts - Historique des contrats d'un employé
@['/employees/:id/contracts']
pub fn (app &App) get_employee_contracts(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.employee_svc.get_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	contracts := app.contract_svc.get_by_employee(id, ctx.user_org)
	return ctx.json(contracts)
}

// update_employee PUT /employees/:id - Mettre à jour un employé
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
	existing := app.employee_svc.get_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	// json2 ignore les @[default] : si is_active est absent du corps, on conserve
	// la valeur actuelle (sinon l'employé serait désactivé par erreur).
	keys := json_keys(body)
	emp := models.Employee{
		...decoded
		id: id // Forcer l'ID depuis l'URL
		organization_id: ctx.user_org
		is_active: if 'is_active' in keys { decoded.is_active } else { existing.is_active }
		// Champs déclaratifs : conservés s'ils sont absents du corps
		cnps_number: if 'cnps_number' in keys {
			dto.normalize_cnps_number(decoded.cnps_number)
		} else {
			existing.cnps_number
		}
		birth_date: if 'birth_date' in keys { decoded.birth_date } else { existing.birth_date }
		salary_type: if 'salary_type' in keys && decoded.salary_type.len > 0 {
			decoded.salary_type.to_upper()
		} else if existing.salary_type.len > 0 {
			existing.salary_type
		} else {
			'M'
		}
	}

	dto.validate_employee(emp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	app.employee_svc.update(emp) or {
		if err.msg().contains('existe déjà') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}

	// Rattachement du N+1 (manager) — validé dans la même organisation, jamais soi-même
	manager_id := decoded.manager_id or { 0 }
	if manager_id == id {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Un employé ne peut pas être son propre manager'))
	}
	if manager_id > 0 {
		app.repo.get_employee_by_id(manager_id, ctx.user_org) or {
			ctx.res.set_status(.bad_request)
			return ctx.json(dto.error_response("Manager introuvable dans l'organisation (id: ${manager_id})"))
		}
	}
	app.repo.set_employee_manager(id, ctx.user_org, manager_id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur mise à jour du manager: ${err}'))
	}

	app.audit_action(mut ctx, 'employee.update', 'employee', id, 'Mise à jour de ${emp.first_name} ${emp.last_name}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Employé mis à jour' })
}

// delete_employee DELETE /employees/:id - Désactiver un employé (soft delete)
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
	app.employee_svc.get_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	app.employee_svc.deactivate(id, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors de la désactivation'))
	}
	app.audit_action(mut ctx, 'employee.delete', 'employee', id, 'Employé désactivé')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Employé désactivé' })
}

// create_contract POST /contracts - Créer un contrat pour un employé
@['/contracts'; post]
pub fn (mut app App) create_contract(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
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
	app.employee_svc.get_by_id(contract.employee_id, ctx.user_org) or {
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
		organization_id: ctx.user_org
		start_date: effective_start
	}

	// Un nouveau contrat (avenant) remplace le précédent : les contrats encore ouverts
	// à sa date de début sont clos la veille. Sinon, à la clôture du nouveau contrat,
	// l'ancien redeviendrait « en vigueur » et la paie continuerait.
	day_before := effective_start.add_days(-1)
	for prev in app.repo.get_contracts_by_employee(ready.employee_id, ctx.user_org) {
		if prev.start_date >= effective_start {
			continue
		}
		still_open := if end := prev.end_date { end >= effective_start } else { true }
		if still_open {
			app.repo.end_contract(prev.id, day_before, ctx.user_org) or {
				ctx.res.set_status(.internal_server_error)
				return ctx.json(dto.error_response('Impossible de clore le contrat précédent : ${err}'))
			}
		}
	}

	new_id := app.contract_svc.create(ready) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}

	app.audit_action(mut ctx, 'contract.create', 'contract', new_id, 'Contrat de l\'employé ${ready.employee_id} : base ${ready.base_salary}')
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Contrat créé' })
}

// EndContractRequest est le corps de PUT /contracts/:id/end.
struct EndContractRequest {
	end_date string // 'YYYY-MM-DD'
}

// end_contract PUT /contracts/:id/end {"end_date":"2026-06-30"} - Clore un contrat
@['/contracts/:id/end'; put]
pub fn (mut app App) end_contract(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	req := json2.decode[EndContractRequest](ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	dto.validate_iso_date(req.end_date, 'end_date') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	contract := app.repo.get_contract_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Contrat introuvable'))
	}
	end := time.parse_format(req.end_date, 'YYYY-MM-DD') or { time.Time{} }
	start_day := contract.start_date.custom_format('YYYY-MM-DD')
	if req.end_date < start_day {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('La date de fin ne peut pas précéder le début du contrat (${start_day})'))
	}
	app.repo.end_contract(id, end, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'contract.end', 'contract', id, 'Fin au ${req.end_date}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Contrat clos au ${req.end_date}' })
}
