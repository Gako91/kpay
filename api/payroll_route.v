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

	contract := app.repo.get_active_contract(req.employee_id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Aucun contrat actif'))
	}

	timesheet := app.repo.get_timesheet(req.employee_id, req.month, req.year) or {
		models.Timesheet{
			employee_id: req.employee_id
			month: req.month
			year: req.year
			hours_worked: 151.67
			overtime_h: 0
		}
	}

	// Cotisations CNPS (Côte d'Ivoire) chargées depuis la base
	cnps_rules := app.repo.get_tax_rules('CI')

	// Ajustements du mois (primes/retenues filtrés par période) + heures supplémentaires
	mut adjustments := app.repo.get_adjustments_for_period(req.employee_id, req.month, req.year)
	overtime_pay := core.calculate_overtime(contract.hourly_rate, timesheet.overtime_h)
	if overtime_pay > 0 {
		adjustments << models.Adjustment{
			employee_id: req.employee_id
			amount: overtime_pay
			description: 'Heures supplémentaires'
		}
	}

	result := core.calculate_pay(contract, cnps_rules, adjustments)
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
@['/payslips/:id/pay'; post]
pub fn (mut app App) mark_payslip_paid(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	mut payroll_service := services.new_payroll_service(mut app.repo)

	payroll_service.mark_paid(id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors du marquage du bulletin'))
	}

	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Bulletin marqué comme payé' })
}

// GET /payslips/:id - Consultation d'un bulletin de paie
@['/payslips/:id']
pub fn (app &App) get_payslip(mut ctx Context, id int) veb.Result {
	dto.validate_id(id, 'payslip_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	payslip := app.repo.get_payslip_by_id(id) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Bulletin non trouvé'))
	}
	return ctx.json(payslip)
}

// run_payroll POST /payroll/run - Génère et sauvegarde la paie mensuelle de tous les employés
@['/payroll/run'; post]
pub fn (mut app App) run_payroll(mut ctx Context) veb.Result {
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
	payslips := payroll_service.run_and_save_monthly_payroll(req.month, req.year) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}

	ctx.res.set_status(.created)
	return ctx.json(dto.RunResponse{ success: true, count: payslips.len, payslips: payslips })
}

// GET /exports/employees/csv - Exporter les employés au format CSV
@['/exports/employees/csv']
pub fn (app &App) export_employees_csv_endpoint(mut ctx Context) veb.Result {
	employees := app.employee_svc.get_all()
	csv_content := services.generate_employees_csv(employees)
	ctx.res.header.set(.content_type, 'text/csv; charset=utf-8')
	return ctx.text(csv_content)
}

// GET /exports/sepa - Générer le fichier de virement SEPA XML
@['/exports/sepa']
pub fn (app &App) export_sepa_endpoint(mut ctx Context) veb.Result {
	employees := app.employee_svc.get_all()
	mut transfers := []services.SepaTransfer{}
	for emp in employees {
		contract := app.repo.get_active_contract(emp.id) or { continue }
		transfers << services.SepaTransfer{
			iban: 'CI93010001001234567890${emp.id:02d}'
			bic: 'BNFACIXX'
			recipient_name: '${emp.first_name} ${emp.last_name}'
			amount: contract.base_salary
			reference: 'SALAIRE-${emp.id}'
		}
	}
	xml_content := services.generate_sepa_xml(transfers)
	ctx.res.header.set(.content_type, 'application/xml; charset=utf-8')
	return ctx.text(xml_content)
}

