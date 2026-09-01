module services

import core
import models
import repository
import time

pub struct PayrollService {
mut:
	repo repository.Repository
}

pub fn new_payroll_service(mut repo repository.Repository) PayrollService {
	return PayrollService{
		repo: repo
	}
}

pub fn (mut s PayrollService) run_monthly_payroll(month int, year int) ![]models.Payslip {
	mut generated_payslips := []models.Payslip{}

	// 1. Récupérer tous les employés actifs
	employees := s.repo.get_all_employees()

	// 2. Récupérer les cotisations CNPS (Côte d'Ivoire)
	rules := s.repo.get_tax_rules('CI')

	for emp in employees {
		// 3. Récupérer le contrat actif de l'employé
		contract := s.repo.get_active_contract(emp.id) or {
			log_warn('Pas de contrat actif pour ${emp.first_name} ${emp.last_name}')
			continue
		}

		// 4. Récupérer les ajustements du mois pour cet employé (filtrés par période)
		adjustments := s.repo.get_adjustments_for_period(emp.id, month, year)

		// 5. Calculer la paie complète (CNPS, CMU, IS, CN, IGR avec quotient familial)
		result := core.calculate_pay_full_ci(contract, rules, adjustments, emp.tax_parts)

		// 6. Créer le bulletin (Payslip)
		period_start := time.Time{
			year: year
			month: month
			day: 1
		}
		period_end := time.Time{
			year: year
			month: month
			day: core.days_in_month(month, year)
		}

		new_payslip := models.Payslip{
			employee_id: emp.id
			period_start: period_start
			period_end: period_end
			gross_amount: result.gross_pay
			total_taxes: result.total_taxes
			net_amount: result.net_pay
		}

		generated_payslips << new_payslip
		log_info('Paie calculée pour ${emp.first_name} ${emp.last_name}: Net ${result.net_pay / 100} FCFA')
	}

	return generated_payslips
}

// run_and_save_monthly_payroll Génère puis sauvegarde les bulletins de paie du mois.
// Toutes les insertions sont enveloppées dans une transaction : en cas d'erreur partielle,
// aucun bulletin n'est persisté (pas de paie incomplète en base).
pub fn (mut s PayrollService) run_and_save_monthly_payroll(month int, year int) ![]models.Payslip {
	payslips := s.run_monthly_payroll(month, year)!

	// Ouvrir la transaction avant toute insertion
	s.repo.begin_transaction()!

	mut saved := []models.Payslip{}
	for payslip in payslips {
		id := s.repo.create_payslip(payslip) or {
			// Une insertion a échoué : on annule tout ce qui a été fait dans cette transaction
			s.repo.rollback()
			return error('Erreur lors de la sauvegarde du bulletin pour employé ${payslip.employee_id}: ${err}')
		}
		saved << models.Payslip{
			...payslip
			id: id
		}
	}

	// Valider la transaction uniquement si tous les bulletins ont été insérés
	s.repo.commit() or {
		s.repo.rollback()
		return error('COMMIT échoué : ${err}')
	}

	log_info('Paie du ${month}/${year} : ${saved.len} bulletins générés et sauvegardés')

	// Notifier les employés pour la mise à disposition de leur bulletin
	mut queue := new_notification_queue()
	for p in saved {
		emp := s.repo.get_employee_by_id(p.employee_id) or { continue }
		queue.push(notify_payslip_generated(emp.email, '${month}/${year}'))
	}

	return saved
}

// mark_paid marque un bulletin de paie comme payé
pub fn (mut s PayrollService) mark_paid(payslip_id int) ! {
	s.repo.mark_payslip_paid(payslip_id)!
	log_info('Bulletin ${payslip_id} marqué comme payé')

	payslip := s.repo.get_payslip_by_id(payslip_id) or { return }
	emp := s.repo.get_employee_by_id(payslip.employee_id) or { return }
	mut queue := new_notification_queue()
	queue.push(notify_payment_processed(emp.email, payslip.id, payslip.net_amount))
}
