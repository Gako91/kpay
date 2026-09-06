module api

import services
import core
import models
import json2
import veb
import dto
import time

// calculate_payroll POST /payroll/calculate
@['/payroll/calculate'; post]
pub fn (app &App) calculate_payroll(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.PayrollRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	contract := app.repo.get_active_contract(req.employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun contrat actif'))
	}

	timesheet := app.repo.get_timesheet(req.employee_id, req.month, req.year, ctx.user_org) or {
		models.Timesheet{
			organization_id: ctx.user_org
			employee_id: req.employee_id
			month: req.month
			year: req.year
			hours_worked: 151.67
			overtime_h: 0
		}
	}

	// Cotisations CNPS (Côte d'Ivoire) chargées depuis la base
	cnps_rules := app.repo.get_tax_rules('CI', ctx.user_org)

	// Ajustements du mois (primes/retenues filtrés par période) + heures supplémentaires CI
	mut adjustments := app.repo.get_adjustments_for_period(req.employee_id, req.month, req.year, ctx.user_org)
	overtime_pay := core.calculate_overtime_ci(contract.hourly_rate, timesheet.overtime_h)
	if overtime_pay > 0 {
		adjustments << models.Adjustment{
			organization_id: ctx.user_org
			employee_id: req.employee_id
			amount: overtime_pay
			description: 'Heures supplémentaires'
		}
	}

	emp := app.repo.get_employee_by_id(req.employee_id, ctx.user_org) or {
		models.Employee{
			id: req.employee_id
			organization_id: ctx.user_org
			tax_parts: 1.0
		}
	}

	result := core.calculate_pay_full_ci(contract, cnps_rules, adjustments, emp.tax_parts)
	services.log_info('Paie calculée pour employé ${req.employee_id}')

	pay_run := models.PayRun{
		employee_id: contract.employee_id
		gross_pay: result.gross_pay
		tax_amount: result.total_taxes
		net_pay: result.net_pay
		date: time.now().format_ss()
	}
	return ctx.json(pay_run)
}

// mark_payslip_paid POST /payslips/:id/pay - Marquage d'un bulletin payé
// Le bulletin doit être approuvé (workflow) avant paiement.
@['/payslips/:id/pay'; post]
pub fn (mut app App) mark_payslip_paid(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	mut payroll_service := services.new_payroll_service(mut app.repo)
	payroll_service.set_mailer(app.mailer_svc)

	payroll_service.mark_paid(ctx.user_org, id) or {
		if err.msg().contains('non approuvé') || err.msg().contains('introuvable') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.error_response(err.msg()))
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors du marquage du bulletin'))
	}
	app.audit_action(mut ctx, 'payslip.pay', 'payslip', id, 'Bulletin payé')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Bulletin marqué comme payé' })
}

// submit_payslip POST /payslips/:id/submit - Transmet un bulletin pour approbation
@['/payslips/:id/submit'; post]
pub fn (mut app App) submit_payslip(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	mut payroll_service := services.new_payroll_service(mut app.repo)
	payroll_service.submit_payslip(ctx.user_org, id) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
			return ctx.json(dto.error_response(err.msg()))
		}
		ctx.res.set_status(.conflict)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'payslip.submit', 'payslip', id, 'Bulletin soumis pour approbation')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Bulletin soumis pour approbation' })
}

// approve_payslip POST /payslips/:id/approve - Approuve un bulletin soumis
@['/payslips/:id/approve'; post]
pub fn (mut app App) approve_payslip(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	mut payroll_service := services.new_payroll_service(mut app.repo)
	payroll_service.approve_payslip(ctx.user_org, id, ctx.user_sub) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
			return ctx.json(dto.error_response(err.msg()))
		}
		ctx.res.set_status(.conflict)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'payslip.approve', 'payslip', id, 'Bulletin approuvé')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Bulletin approuvé' })
}

// reject_payslip POST /payslips/:id/reject - Refuse un bulletin soumis (retour brouillon)
@['/payslips/:id/reject'; post]
pub fn (mut app App) reject_payslip(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	mut payroll_service := services.new_payroll_service(mut app.repo)
	payroll_service.reject_payslip(ctx.user_org, id) or {
		if err.msg().contains('introuvable') {
			ctx.res.set_status(.not_found)
			return ctx.json(dto.error_response(err.msg()))
		}
		ctx.res.set_status(.conflict)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'payslip.reject', 'payslip', id, 'Bulletin rejeté — retour en brouillon')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Bulletin rejeté' })
}

// GET /payslips/:id - Consultation d'un bulletin de paie
@['/payslips/:id']
pub fn (app &App) get_payslip(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	payslip := app.repo.get_payslip_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Bulletin non trouvé'))
	}
	return ctx.json(payslip)
}

// GET /payslips - Liste des bulletins, filtrables par période (période courante par défaut)
@['/payslips']
pub fn (app &App) list_payslips(mut ctx Context) veb.Result {
	month := if ctx.query['month'].len > 0 {
		ctx.query['month'].int()
	} else {
		time.now().month
	}
	year := if ctx.query['year'].len > 0 {
		ctx.query['year'].int()
	} else {
		time.now().year
	}
	payslips := app.repo.get_payslips_by_period(month, year, ctx.user_org)
	return ctx.json(payslips)
}

// GET /employees/:id/payslips - Historique des bulletins d'un employé
@['/employees/:id/payslips']
pub fn (app &App) get_employee_payslips(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'employee_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.employee_svc.get_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	payslips := app.repo.get_payslips_by_employee(id, ctx.user_org)
	return ctx.json(payslips)
}

// GET /payslips/:id/pdf - Téléchargement du bulletin de paie au format PDF
@['/payslips/:id/pdf']
pub fn (mut app App) get_payslip_pdf(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	return app.render_payslip_pdf(mut ctx, id)
}

// run_payroll POST /payroll/run - Génère et sauvegarde la paie mensuelle de tous les employés
@['/payroll/run'; post]
pub fn (mut app App) run_payroll(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'payroll_officer']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	req := json2.decode[dto.PayrollRunRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}

	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	mut payroll_service := services.new_payroll_service(mut app.repo)
	payroll_service.set_mailer(app.mailer_svc)
	payslips := payroll_service.run_and_save_monthly_payroll(ctx.user_org, req.month, req.year) or {
		if err.msg().contains('déjà été générée') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.error_response(err.msg()))
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'payroll.run', 'payroll', 0, 'Paie ${req.month}/${req.year} — ${payslips.len} bulletins générés')

	ctx.res.set_status(.created)
	return ctx.json(dto.RunResponse{ success: true, count: payslips.len, payslips: payslips })
}

// GET /exports/employees/csv - Exporter les employés au format CSV
@['/exports/employees/csv']
pub fn (app &App) export_employees_csv_endpoint(mut ctx Context) veb.Result {
	employees := app.employee_svc.get_all(ctx.user_org)
	csv_content := services.generate_employees_csv(employees)
	ctx.res.header.set(.content_type, 'text/csv; charset=utf-8')
	return ctx.text(csv_content)
}

// GET /exports/sepa - Générer le fichier de virement SEPA XML
@['/exports/sepa']
pub fn (app &App) export_sepa_endpoint(mut ctx Context) veb.Result {
	employees := app.employee_svc.get_all(ctx.user_org)
	// Anomalie RIB : demandes IBAN/BIC en attente de validation RH (signalées dans le virement)
	pending_rib := app.repo.get_pending_rib_changes(ctx.user_org)
	mut transfers := []services.SepaTransfer{}
	for emp in employees {
		contract := app.repo.get_active_contract(emp.id, ctx.user_org) or { continue }
		iban := if emp.iban.len > 0 { emp.iban } else { 'CI93010001001234567890${emp.id:02d}' }
		bic := if emp.bic.len > 0 { emp.bic } else { 'BNFACIXX' }
		transfers << services.SepaTransfer{
			iban: iban
			bic: bic
			recipient_name: '${emp.first_name} ${emp.last_name}'
			amount: contract.base_salary
			reference: 'SALAIRE-${emp.id}'
			rib_pending: pending_rib[emp.id].len > 0
		}
	}
	xml_content := services.generate_sepa_xml(transfers)
	ctx.res.header.set(.content_type, 'application/xml; charset=utf-8')
	return ctx.text(xml_content)
}

// GET /payroll/book - Livre de Paie mensuel au format JSON
@['/payroll/book']
pub fn (app &App) get_payroll_book_json(mut ctx Context) veb.Result {
	month := ctx.query['month'] or { '9' }.int()
	year := ctx.query['year'] or { '2026' }.int()

	book := app.payroll_svc.get_payroll_book(ctx.user_org, month, year)
	return ctx.json(book)
}

// GET /payroll/book/csv - Livre de Paie mensuel au format CSV
@['/payroll/book/csv']
pub fn (app &App) get_payroll_book_csv(mut ctx Context) veb.Result {
	month := ctx.query['month'] or { '9' }.int()
	year := ctx.query['year'] or { '2026' }.int()

	book := app.payroll_svc.get_payroll_book(ctx.user_org, month, year)
	csv_content := services.generate_payroll_book_csv(book)

	ctx.res.header.set(.content_type, 'text/csv; charset=utf-8')
	ctx.res.header.set_custom('Content-Disposition', 'attachment; filename="livre_de_paie_${month}_${year}.csv"') or {}
	return ctx.text(csv_content)
}

// GET /payroll/book/pdf - Livre de Paie mensuel au format PDF récapitulatif
@['/payroll/book/pdf']
pub fn (app &App) get_payroll_book_pdf(mut ctx Context) veb.Result {
	month := ctx.query['month'] or { '9' }.int()
	year := ctx.query['year'] or { '2026' }.int()

	book := app.payroll_svc.get_payroll_book(ctx.user_org, month, year)
	pdf_bytes := services.generate_payroll_book_pdf(book) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors de la génération du PDF du Livre de Paie'))
	}

	ctx.res.header.set(.content_type, 'application/pdf')
	ctx.res.header.set_custom('Content-Disposition', 'inline; filename="livre_de_paie_${month}_${year}.pdf"') or {}
	return ctx.send_response_to_client('application/pdf', pdf_bytes.bytestr())
}
