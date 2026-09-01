module data

import models
import repository
import time

// Seed des données initiales via le Repository
pub fn seed_data(mut repo repository.Repository) ! {
	// Vérifier si les règles CNPS pour la Côte d'Ivoire existent déjà
	// (on vérifie par pays pour ne pas bloquer si des règles d'autres pays sont présentes)
	existing_ci_rules := repo.get_tax_rules('CI')
	if existing_ci_rules.len > 0 {
		return
	}

	// Barème officiel CNPS & Cotisations Sociales (Côte d'Ivoire)
	// - Plafond Régime Général Retraite : 45 SMIG = 3 375 000 FCFA / mois
	// - Plafond Prestations Familiales & Accidents du Travail : 70 000 FCFA / mois
	// - CMU (Couverture Maladie Universelle) : 1 000 FCFA / mois forfaitaire
	rules := [
		models.TaxRule{
			name: 'CNPS Retraite (part salariale)'
			rate: 0.063
			is_employer: false
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CMU Salarié'
			rate: 0.0
			is_employer: false
			fixed_amount: 1_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Retraite (part patronale)'
			rate: 0.077
			is_employer: true
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Prestations Familiales (part patronale)'
			rate: 0.0575
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Accident du Travail (part patronale)'
			rate: 0.02
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Régime Complémentaire (part patronale)'
			rate: 0.012
			is_employer: true
			ceiling: 3_375_000
			country: 'CI'
		},
	]

	for rule in rules {
		repo.create_tax_rule(rule)!
	}

	// Initialiser un employé, contrat et bulletin exemple si la base est vide
	existing_employees := repo.get_all_employees()
	if existing_employees.len == 0 {
		emp := models.Employee{
			first_name: 'Koffi'
			last_name: 'Kouamé'
			email: 'koffi.kouame@example.com'
			iban: 'CI9301000100123456789001'
			bic: 'BNFACIXX'
			is_active: true
		}
		emp_id := repo.create_employee(emp) or { 0 }
		if emp_id > 0 {
			contract := models.Contract{
				employee_id: emp_id
				base_salary: 400000
				hourly_rate: 2500
				currency: 'XOF'
			}
			repo.create_contract(contract) or {}

			period_start := time.Time{ year: 2026, month: 8, day: 1 }
			period_end := time.Time{ year: 2026, month: 8, day: 31 }
			payslip := models.Payslip{
				employee_id: emp_id
				period_start: period_start
				period_end: period_end
				gross_amount: 400000
				total_taxes: 19480
				net_amount: 380520
				is_paid: true
			}
			repo.create_payslip(payslip) or {}
		}
	}
}
