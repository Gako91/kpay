module data

import models
import repository
import common
import services
import os
import time

// Seed des données initiales via le Repository
pub fn seed_data(mut repo repository.Repository) ! {
	seed_platform_org(mut repo)!
	seed_admin_user(mut repo)!
	seed_cnps_rules(mut repo)!
}

// seed_platform_org garantit l'existence de l'organisation plateforme (id 1).
// Les tenants créés via /admin/organizations reçoivent ensuite les ids suivants.
fn seed_platform_org(mut repo repository.Repository) ! {
	if repo.get_organization_by_id(1) != none {
		return
	}
	repo.create_organization(models.Organization{
		id: 1
		name: 'KPay Platform'
		tax_id: 'PLATFORM'
		currency: 'XOF'
	})!
	services.log_info("Organisation plateforme 'KPay Platform' (org 1) créée")
}

// seed_admin_user crée un compte administrateur par défaut pour l'organisation 1
// si aucune n'existe encore pour ce tenant.
fn seed_admin_user(mut repo repository.Repository) ! {
	if repo.get_all_users(1).len > 0 {
		return
	}
	username := os.getenv_opt('KPAY_ADMIN_USERNAME') or { 'admin' }
	password := os.getenv_opt('KPAY_ADMIN_PASSWORD') or { 'admin123' }
	repo.create_user(models.User{
		username: username
		password_hash: common.hash_password(password)
		role: 'admin'
		email: 'admin@kpay.local'
		organization_id: 1
		is_active: true
		created_at: time.now()
	})!
	services.log_info('Compte administrateur par défaut créé (org 1): ${username}')
}

// seed_cnps_rules initialise les règles CNPS de l'organisation 1 et un exemple
// s'il n'existe pas déjà.
fn seed_cnps_rules(mut repo repository.Repository) ! {
	// Vérifier si les règles CNPS pour la Côte d'Ivoire existent déjà
	// (on vérifie par pays pour ne pas bloquer si des règles d'autres pays sont présentes)
	existing_ci_rules := repo.get_tax_rules('CI', 1)
	if existing_ci_rules.len > 0 {
		return
	}

	// Barème officiel CNPS & Cotisations Sociales (Côte d'Ivoire)
	// - Plafond Régime Général Retraite : 45 SMIG = 3 375 000 FCFA / mois
	// - Plafond Prestations Familiales & Accidents du Travail : 70 000 FCFA / mois
	// - CMU (Couverture Maladie Universelle) : 1 000 FCFA / mois forfaitaire
	rules := [
		models.TaxRule{
			organization_id: 1
			name: 'CNPS Retraite (part salariale)'
			rate: 0.063
			is_employer: false
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			organization_id: 1
			name: 'CMU Salarié'
			rate: 0.0
			is_employer: false
			fixed_amount: 1_000
			country: 'CI'
		},
		models.TaxRule{
			organization_id: 1
			name: 'CNPS Retraite (part patronale)'
			rate: 0.077
			is_employer: true
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			organization_id: 1
			name: 'CNPS Prestations Familiales (part patronale)'
			rate: 0.0575
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			organization_id: 1
			name: 'CNPS Accident du Travail (part patronale)'
			rate: 0.02
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			organization_id: 1
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
	existing_employees := repo.get_all_employees(1)
	if existing_employees.len == 0 {
		emp := models.Employee{
			organization_id: 1
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
				organization_id: 1
				employee_id: emp_id
				base_salary: 400000
				hourly_rate: 2500
				currency: 'XOF'
			}
			repo.create_contract(contract) or {}

			period_start := time.Time{ year: 2026, month: 8, day: 1 }
			period_end := time.Time{ year: 2026, month: 8, day: 31 }
			payslip := models.Payslip{
				organization_id: 1
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