module api

import models
import json2
import veb
import dto

// GET /employees
@['/employees']
pub fn (app &App) get_employees(mut ctx Context) veb.Result {
	employees := app.employee_svc.get_all()
	return ctx.json(employees)
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
