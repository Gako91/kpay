module main

import os
import time
import models
import core
import services

fn main() {
	payslip := models.Payslip{
		id: 3
		employee_id: 1
		period_start: time.Time{ year: 2026, month: 8, day: 1 }
		period_end: time.Time{ year: 2026, month: 8, day: 31 }
		gross_amount: 400000
		total_taxes: 16480
		net_amount: 383520
		is_paid: true
	}
	emp := models.Employee{
		id: 1
		first_name: 'Koffi'
		last_name: 'Kouame'
		email: 'koffi.kouame@example.ci'
		iban: 'CI9301000100123456789001'
		bic: 'BNFACIXX'
		is_active: true
	}
	contract := models.Contract{
		employee_id: 1
		base_salary: 400000
		hourly_rate: 2500
	}
	tax_details := [
		core.TaxLine{ name: 'CNPS Retraite (part salariale)', amount: 16480 },
		core.TaxLine{ name: 'CNPS Maladie-Maternite (part salariale)', amount: 3000 },
	]

	// regen
	path := services.generate_and_store_payslip_pdf(payslip, emp, contract, tax_details) or {
		println('Erreur: ${err}')
		return
	}
	println('Genere avec succes: ${path}')
}
