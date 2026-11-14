module services

import time
import models

fn day(y int, m int, d int) time.Time {
	return time.Time{
		year: y
		month: m
		day: d
	}
}

fn slip(emp_id int, month int, gross i64, status string) models.Payslip {
	return models.Payslip{
		employee_id: emp_id
		period_start: day(2026, month, 1)
		period_end: day(2026, month, 28)
		gross_amount: gross
		status: status
	}
}

fn complete_employee(id int) models.Employee {
	return models.Employee{
		id: id
		first_name: 'Jean-Marc'
		last_name: "N'Guessan Kouassi"
		cnps_number: '012345678901'
		birth_date: '1990-03-15'
		salary_type: 'M'
	}
}

fn test_disa_name_normalisation() {
	assert disa_name("N'Guessan-Kouassi") == 'N GUESSAN KOUASSI'
	assert disa_name('  Éloïse   Adjoa ') == 'ELOISE ADJOA'
	assert disa_name('Koné (dit Ali) 2') == 'KONE DIT ALI'
}

fn test_build_disa_complete_employee() {
	report := build_disa(DisaInput{
		year: 2026
		employees: [complete_employee(1)]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2020, 2, 1)
			},
		]
		payslips: [slip(1, 1, 400000, models.status_paye),
			slip(1, 2, 400000, models.status_approuve),
			slip(1, 3, 999999, models.status_rejete)]
	})
	assert report.blocking_count == 0
	assert report.rows.len == 1
	r := report.rows[0]
	assert r.cnps_number == '012345678901'
	assert r.last_name == 'N GUESSAN KOUASSI'
	assert r.first_names == 'JEAN MARC'
	assert r.birth_date == '15/03/1990'
	assert r.hire_date == '01/02/2020'
	assert r.departure_date == ''
	assert r.salary_type == 'M'
	assert r.work_time == 2.0 // le bulletin rejeté ne compte pas
	assert r.annual_gross == 800000
	assert report.total_gross == 800000
}

fn test_build_disa_departure_and_rehire() {
	// Départ en cours d'année : date de fin du dernier contrat
	report := build_disa(DisaInput{
		year: 2026
		employees: [complete_employee(1)]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2019, 1, 1)
				end_date: day(2024, 6, 30)
			},
			models.Contract{
				employee_id: 1
				start_date: day(2025, 1, 1)
				end_date: day(2026, 6, 30)
			},
		]
		payslips: [slip(1, 1, 300000, models.status_paye)]
	})
	assert report.rows[0].hire_date == '01/01/2019'
	assert report.rows[0].departure_date == '30/06/2026'

	// Contrat clos après la fin de l'année : toujours en poste au 31/12
	still := build_disa(DisaInput{
		year: 2026
		employees: [complete_employee(1)]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2025, 1, 1)
				end_date: day(2027, 3, 31)
			},
		]
		payslips: [slip(1, 1, 300000, models.status_paye)]
	})
	assert still.rows[0].departure_date == ''
}

fn test_build_disa_blocking_issues() {
	incomplete := models.Employee{
		id: 2
		first_name: 'Awa'
		last_name: 'Traoré'
		cnps_number: '12345'
	}
	report := build_disa(DisaInput{
		year: 2026
		employees: [complete_employee(1), incomplete]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2020, 1, 1)
			},
		]
		payslips: [slip(1, 1, 400000, models.status_paye), slip(1, 2, 400000, models.status_brouillon),
			slip(2, 1, 200000, models.status_paye)]
	})
	fields := report.issues.filter(it.blocking).map('${it.employee_id}:${it.field}')
	assert '1:bulletins' in fields // bulletin de février encore en brouillon
	assert '2:cnps_number' in fields
	assert '2:birth_date' in fields
	assert '2:contract' in fields
	assert report.blocking_count == fields.len
}

fn test_build_disa_skips_employees_without_payslips() {
	report := build_disa(DisaInput{
		year: 2026
		employees: [models.Employee{
			id: 3
			first_name: 'Sans'
			last_name: 'Bulletin'
		}]
	})
	assert report.rows.len == 0
	assert report.issues.len == 0
}

fn test_build_disa_hourly_and_floor_warning() {
	mut emp := complete_employee(1)
	emp = models.Employee{
		...emp
		salary_type: 'H'
	}
	report := build_disa(DisaInput{
		year: 2026
		employees: [emp]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2026, 1, 1)
			},
		]
		payslips: [slip(1, 1, 50000, models.status_paye)]
		timesheets: [
			models.Timesheet{
				employee_id: 1
				month: 1
				year: 2026
				hours_worked: 100
				overtime_h: 4
			},
		]
	})
	assert report.blocking_count == 0
	assert report.rows[0].work_time == 104.0

	low := build_disa(DisaInput{
		year: 2026
		employees: [complete_employee(1)]
		contracts: [
			models.Contract{
				employee_id: 1
				start_date: day(2026, 1, 1)
			},
		]
		payslips: [slip(1, 1, 50000, models.status_paye)]
	})
	assert low.blocking_count == 0
	assert low.issues.len == 1
	assert low.issues[0].field == 'annual_gross'
}

fn sealed_entry(prev string, id int, version int) models.DeclarationExport {
	base := models.DeclarationExport{
		id: id
		organization_id: 1
		kind: 'disa'
		period: '2026'
		version: version
		sha256: 'abc${id}'
		prev_hash: prev
		row_count: 3
		total_amount: 1000
		created_by: 'admin'
		sealed_at: '2026-11-14T10:00:00Z'
	}
	return models.DeclarationExport{
		...base
		chain_hash: models.declaration_chain_hash(prev, base)
	}
}

fn test_verify_declaration_chain() {
	a := sealed_entry('', 1, 1)
	b := sealed_entry(a.chain_hash, 2, 2)
	c := sealed_entry(b.chain_hash, 3, 3)
	assert verify_declaration_chain([a, b, c]).ok

	// Entrée supprimée au milieu
	gap := verify_declaration_chain([a, c])
	assert !gap.ok
	assert gap.broken_id == 3

	// Métadonnée modifiée (montant déclaré)
	tampered := models.DeclarationExport{
		...b
		total_amount: 999
	}
	bad := verify_declaration_chain([a, tampered, c])
	assert !bad.ok
	assert bad.broken_id == 2
}
