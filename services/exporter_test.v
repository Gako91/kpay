module services

import models
import time

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

fn test_generate_payslips_csv() {
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

