module services

import models
import time
import core
import os

fn test_generate_sepa_xml() {
	transfers := [
		SepaTransfer{
			iban: 'CI9301000100123456789001'
			bic: 'BNFACIXX'
			recipient_name: 'Koffi Kouamé'
			amount: 50000000 // 500.000,00 FCFA en centimes
			reference: 'SALAIRE-001'
		},
	]

	xml := generate_sepa_xml(transfers)
	assert xml.contains('pain.001.001.03')
	assert xml.contains('SALAIRE-001')
	assert xml.contains('Koffi Kouamé')
	assert xml.contains('500000.00')
	assert xml.contains('CI9301000100123456789001')
}

fn test_generate_employees_csv() {
	employees := [
		models.Employee{
			id: 1
			first_name: 'Jean'
			last_name: 'Dupont'
			email: 'jean.dupont@example.com'
			is_active: true
		},
	]

	csv := generate_employees_csv(employees)
	assert csv.contains('ID,First Name,Last Name,Email,Active')
	assert csv.contains('1,"Jean","Dupont","jean.dupont@example.com",true')
}

fn test_generate_payslip_csv() {
	payslips := [
		models.Payslip{
			id: 10
			employee_id: 1
			period_start: time.Time{ year: 2026, month: 1, day: 1 }
			period_end: time.Time{ year: 2026, month: 1, day: 31 }
			gross_amount: 60000000
			total_taxes: 10000000
			net_amount: 50000000
			is_paid: true
		},
	]

	csv := generate_payslips_csv(payslips)
	assert csv.contains('ID,EmployeeID,PeriodStart,PeriodEnd,GrossAmount,TotalTaxes,NetAmount,Paid')
	assert csv.contains('10,1,')
	assert csv.contains('60000000,10000000,50000000,true')
}

fn test_generate_payslip_pdf() {
	payslip := models.Payslip{
		id: 1
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
		last_name: 'Kouame' // sanitize_pdf_text gère les accents en production
		email: 'koffi@example.com'
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

	pdf_bytes := generate_payslip_pdf(payslip, emp, contract, tax_details) or {
		assert false, 'generate_payslip_pdf a echoue: ${err}'
		return
	}

	assert pdf_bytes.len > 0, 'Le PDF ne doit pas etre vide'
	// Le header magique d'un fichier PDF valide commence par %PDF-
	pdf_str := pdf_bytes.bytestr()
	assert pdf_str.starts_with('%PDF-'), 'Le PDF doit commencer par %PDF-'

	// Vérifier le bon fonctionnement du formatage monétaire avec séparateurs
	assert format_fcfa(payslip.gross_amount) == '400 000 FCFA'
	assert format_fcfa(payslip.net_amount) == '383 520 FCFA'
	assert format_fcfa(1234567) == '1 234 567 FCFA'
	assert format_fcfa(500) == '500 FCFA'

	os.write_file('/tmp/test_bulletin.pdf', pdf_str) or {}
}

fn test_generate_and_store_payslip_pdf() {
	payslip := models.Payslip{
		id: 99
		employee_id: 1
		period_start: time.Time{ year: 2026, month: 8, day: 1 }
		period_end: time.Time{ year: 2026, month: 8, day: 31 }
		gross_amount: 500000
		total_taxes: 24350
		net_amount: 475650
		is_paid: false
	}
	emp := models.Employee{
		id: 1
		first_name: 'Aya'
		last_name: 'Kone'
		email: 'aya.kone@example.com'
		is_active: true
	}
	contract := models.Contract{
		employee_id: 1
		base_salary: 500000
		hourly_rate: 3000
	}
	tax_details := [
		core.TaxLine{ name: 'CNPS Retraite (part salariale)', amount: 20600 },
	]

	// Nettoyer un éventuel fichier résiduel du test précédent
	os.rm('storage/payslips/bulletin_99.pdf') or {}

	stored_path := generate_and_store_payslip_pdf(payslip, emp, contract, tax_details) or {
		assert false, 'generate_and_store_payslip_pdf a echoue: ${err}'
		return
	}

	assert stored_path == 'storage/payslips/bulletin_99.pdf'
	assert os.exists(stored_path), 'Le fichier PDF doit exister sur disque'

	// Appel idempotent : doit retourner le même chemin sans regénérer
	stored_path2 := generate_and_store_payslip_pdf(payslip, emp, contract, tax_details) or {
		assert false
		return
	}
	assert stored_path2 == stored_path

	// Nettoyage
	os.rm(stored_path) or {}
}
