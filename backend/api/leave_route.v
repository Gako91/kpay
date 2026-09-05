module api

import veb
import dto
import models
import time
import json2

// CreateLeaveRequestInput définit le body pour soumettre une demande de congé
pub struct CreateLeaveRequestInput {
pub:
	employee_id int
	leave_type  string
	start_date  string // YYYY-MM-DD
	end_date    string // YYYY-MM-DD
	days_count  f32
	reason      string
}

// UpdateLeaveStatusInput définit le body pour approuver/refuser un congé
pub struct UpdateLeaveStatusInput {
pub:
	status string // 'approuve' | 'refuse'
}

// POST /leaves - Soumettre une demande de congé
@['/leaves'; post]
pub fn (mut app App) create_leave(mut ctx Context) veb.Result {
	body := ctx.req.data
	input := json2.decode[CreateLeaveRequestInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	start := time.parse_iso8601(input.start_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format start_date invalide (YYYY-MM-DD attendu)'))
	}
	end := time.parse_iso8601(input.end_date) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Format end_date invalide (YYYY-MM-DD attendu)'))
	}

	req := models.LeaveRequest{
		employee_id: input.employee_id
		leave_type: input.leave_type
		start_date: start
		end_date: end
		days_count: input.days_count
		reason: input.reason
	}

	created := app.repo.create_leave_request(req) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur creation demande de conge: ${err}'))
	}

	app.audit_action(mut ctx, 'CREATE', 'leave_request', created.id, 'Demande de congé créée pour employé ${created.employee_id}')

	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{
		success: true
		data: '${created.id}'
		message: 'Demande de congé soumise avec succès'
	})
}

// GET /leaves - Lister les demandes de congé (Admin / RH ou filtre par employé)
@['/leaves']
pub fn (mut app App) get_leaves(mut ctx Context) veb.Result {
	emp_id_str := ctx.query['employee_id']
	if emp_id_str.len > 0 {
		emp_id := emp_id_str.int()
		requests := app.repo.get_leave_requests_by_employee(emp_id) or {
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
		}
		return ctx.json(requests)
	}

	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}

	requests := app.repo.get_all_leave_requests() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur chargement demandes de conge'))
	}

	return ctx.json(requests)
}

// PUT /leaves/:id/status - Valider ou refuser une demande de congé (Admin / RH)
@['/leaves/:id/status'; put]
pub fn (mut app App) update_leave_status(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}

	body := ctx.req.data
	input := json2.decode[UpdateLeaveStatusInput](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	if input.status != 'approuve' && input.status != 'refuse' {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Statut invalide. Valeurs autorisees: 'approuve', 'refuse'"))
	}

	app.repo.update_leave_status(id, input.status, ctx.user_sub) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur mise à jour statut conge: ${err}'))
	}

	app.audit_action(mut ctx, 'UPDATE_STATUS', 'leave_request', id, 'Demande de congé passe à ${input.status}')

	return ctx.json(dto.ApiResponse{
		success: true
		data: '${id}'
		message: 'Statut mis à jour avec succès'
	})
}
