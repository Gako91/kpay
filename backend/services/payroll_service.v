module services

import core
import models
import repository
import dto
import time

pub struct PayrollService {
mut:
	repo   repository.Repository
	mailer MailerService
}

pub fn new_payroll_service(mut repo repository.Repository) PayrollService {
	return PayrollService{
		repo: repo
		mailer: MailerService{}
	}
}

// set_mailer attache le service d'envoi d'emails aux notifications.
pub fn (mut s PayrollService) set_mailer(m MailerService) {
	s.mailer = m
}

// EmpPayoutTask regroupe toutes les entrées nécessaires au calcul de paie d'un
// seul employé. Les calculs sont de pures fonctions (fan-out) : chaque tâche est
// indépendante et peut donc être exécutée en parallèle via `spawn`.
struct EmpPayoutTask {
	idx         int
	emp_id      int
	contract    models.Contract
	adjustments []models.Adjustment
	tax_parts   f32
}

// CalcOut achemine le résultat d'un calcul fan-out vers l'agrégateur.
struct CalcOut {
	idx    int
	result core.CalculationResult
}

// payout_worker calcule la paie d'un employé (fonction pure) et pousse le résultat
// dans le canal partagé. Eff_components/eff_brackets/rules sont en lecture seule,
// sélectionnées une seule fois dans `run_and_save_monthly_payroll`.
fn payout_worker(ch chan CalcOut, task EmpPayoutTask, use_config bool, eff_components []models.TaxComponent, eff_brackets []models.TaxBracket, rules []models.TaxRule) {
	mut result := core.CalculationResult{}
	if use_config {
		result = core.compute_payslip_configurable(task.contract, eff_components, eff_brackets, task.adjustments,
			task.tax_parts)
	} else {
		result = core.calculate_pay_full_ci(task.contract, rules, task.adjustments, task.tax_parts)
	}
	ch <- CalcOut{
		idx: task.idx
		result: result
	}
}

// run_and_save_monthly_payroll Génère puis sauvegarde les bulletins de paie du mois d'une organisation.
// Le calcul de chaque bulletin est une fonction pure exécutée en parallèle (fan-out) ;
// les insertions restent séquentielles et transactionnelles : en cas d'erreur partielle,
// aucun bulletin n'est persisté (pas de paie incomplète en base).
// Une exécution déjà effectuée pour la même période est refusée (idempotence).
// Le callback `progress` (optionnel) reçoit la progression 0-100 du job (Pilier 4 : SSE).
pub fn (mut s PayrollService) run_and_save_monthly_payroll(org_id int, month int, year int, progress fn (int)) ![]models.Payslip {
	if progress != unsafe { nil } {
		progress(2)
	}
	// Idempotence : refuser si la paie de cette période a déjà été générée
	if s.repo.exists_payslip_for_period(month, year, org_id) {
		if progress != unsafe { nil } {
			progress(100)
		}
		return error('La paie de ${month}/${year} a déjà été générée. Utilisez la correction de bulletin si nécessaire.')
	}

	period_date := '${year:04d}-${month:02d}-01'

	// 1. Récupérer les données partagées (cotisations, barèmes)
	rules := s.repo.get_tax_rules('CI', org_id)
	components := s.repo.get_components(org_id)
	brackets := s.repo.get_brackets(org_id)
	use_config := components.len > 0
	mut eff_components := []models.TaxComponent{}
	mut eff_brackets := []models.TaxBracket{}
	if use_config {
		eff_components = core.select_effective_components(components, period_date)
		eff_brackets = core.select_effective_brackets(brackets, period_date)
	}

	// 2. Construire les tâches (séquentiel : I/O base dans la goroutine du worker)
	employees := s.repo.get_all_employees(org_id)
	mut tasks := []EmpPayoutTask{}
	for emp in employees {
		contract := s.repo.get_active_contract(emp.id, org_id) or {
			log_warn('Pas de contrat actif pour ${emp.first_name} ${emp.last_name}')
			continue
		}
		adjustments := s.repo.get_adjustments_for_period(emp.id, month, year, org_id)
		tasks << EmpPayoutTask{
			idx: tasks.len
			emp_id: emp.id
			contract: contract
			adjustments: adjustments
			tax_parts: emp.tax_parts
		}
	}
	if progress != unsafe { nil } {
		progress(20)
	}

	// 3. Fan-out : calculs purs en parallèle, agrégation par index de tâche
	mut ch := chan CalcOut{
		cap: tasks.len
	}
	for t in tasks {
		spawn payout_worker(ch, t, use_config, eff_components, eff_brackets, rules)
	}
	mut results := []core.CalculationResult{len: tasks.len}
	for _ in 0 .. tasks.len {
		out := <-ch
		results[out.idx] = out.result
	}
	if progress != unsafe { nil } {
		progress(60)
	}

	// 4. Construire les bulletins à partir des résultats
	mut payslips := []models.Payslip{}
	for i in 0 .. tasks.len {
		task := tasks[i]
		result := results[i]
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
		payslips << models.Payslip{
			organization_id: org_id
			employee_id: task.emp_id
			period_start: period_start
			period_end: period_end
			gross_amount: result.gross_pay
			total_taxes: result.total_taxes
			net_amount: result.net_pay
			status: models.status_brouillon
		}
	}

	// 5. Ouvrir la transaction avant toute insertion
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

	// 6. Valider la transaction uniquement si tous les bulletins ont été insérés
	s.repo.commit() or {
		s.repo.rollback()
		return error('COMMIT échoué : ${err}')
	}

	if progress != unsafe { nil } {
		progress(85)
	}
	log_info('Paie du ${month}/${year} : ${saved.len} bulletins générés et sauvegardés')

	// 7. Notifier les employés pour la mise à disposition de leur bulletin
	mut queue := new_notification_queue()
	for p in saved {
		emp := s.repo.get_employee_by_id(p.employee_id, org_id) or { continue }
		queue.push(notify_payslip_generated(emp.email, '${month}/${year}'))
	}
	mut dispatcher := new_notification_dispatcher()
	dispatcher.mailer = s.mailer
	dispatcher.queue = queue
	dispatcher.dispatch_all()

	if progress != unsafe { nil } {
		progress(100)
	}
	return saved
}

// mark_paid marque un bulletin de paie comme payé.
// Le bulletin doit être approuvé (workflow) avant le paiement.
pub fn (mut s PayrollService) mark_paid(org_id int, payslip_id int) ! {
	payslip := s.repo.get_payslip_by_id(payslip_id, org_id) or {
		return error('Bulletin ${payslip_id} introuvable')
	}
	if payslip.status != models.status_approuve {
		return error("Bulletin ${payslip_id} non approuvé — statut '${payslip.status}', approuvez-le d'abord")
	}
	s.repo.mark_payslip_paid(payslip_id, org_id)!
	log_info('Bulletin ${payslip_id} marqué comme payé')

	emp := s.repo.get_employee_by_id(payslip.employee_id, org_id) or { return }
	mut queue := new_notification_queue()
	queue.push(notify_payment_processed(emp.email, payslip.id, payslip.net_amount))
	mut dispatcher := new_notification_dispatcher()
	dispatcher.mailer = s.mailer
	dispatcher.queue = queue
	dispatcher.dispatch_all()
}

// submit_payslip transmet un bulletin pour approbation (brouillon/rejeté → soumis).
pub fn (mut s PayrollService) submit_payslip(org_id int, payslip_id int) ! {
	payslip := s.repo.get_payslip_by_id(payslip_id, org_id) or {
		return error('Bulletin ${payslip_id} introuvable')
	}
	if payslip.status != models.status_brouillon && payslip.status != models.status_rejete {
		return error("Seul un bulletin 'brouillon' ou rejeté peut être soumis (statut actuel: '${payslip.status}')")
	}
	s.repo.update_payslip_status(payslip_id, models.status_soumis, org_id)!
	log_info('Bulletin ${payslip_id} soumis pour approbation')
}

// approve_payslip approuve un bulletin soumis.
pub fn (mut s PayrollService) approve_payslip(org_id int, payslip_id int, approver string) ! {
	payslip := s.repo.get_payslip_by_id(payslip_id, org_id) or {
		return error('Bulletin ${payslip_id} introuvable')
	}
	if payslip.status != models.status_soumis {
		return error("Seul un bulletin 'soumis' peut être approuvé (statut actuel: '${payslip.status}')")
	}
	s.repo.approve_payslip(payslip_id, approver, org_id)!
	log_info('Bulletin ${payslip_id} approuvé par ${approver}')
}

// reject_payslip refuse un bulletin soumis et le renvoie en brouillon.
pub fn (mut s PayrollService) reject_payslip(org_id int, payslip_id int) ! {
	payslip := s.repo.get_payslip_by_id(payslip_id, org_id) or {
		return error('Bulletin ${payslip_id} introuvable')
	}
	if payslip.status != models.status_soumis {
		return error("Seul un bulletin 'soumis' peut être rejeté (statut actuel: '${payslip.status}')")
	}
	s.repo.update_payslip_status(payslip_id, models.status_brouillon, org_id)!
	log_info('Bulletin ${payslip_id} rejeté — retour en brouillon')
}

// get_payroll_book calcule et consolide le Livre de Paie pour un mois donné
pub fn (s &PayrollService) get_payroll_book(org_id int, month int, year int) dto.PayrollBookResponse {
	// Filtrage en base pour éviter de charger toute la table en mémoire
	all_payslips := s.repo.get_payslips_by_period(month, year, org_id)
	mut items := []dto.PayrollBookItem{}
	mut total_gross := i64(0)
	mut total_taxes := i64(0)
	mut total_net := i64(0)

	for p in all_payslips {
		emp := s.repo.get_employee_by_id(p.employee_id, org_id) or { continue }

		items << dto.PayrollBookItem{
			payslip_id: p.id
			employee_id: emp.id
			matricule: 'EMP-${emp.id:04d}'
			full_name: '${emp.first_name} ${emp.last_name}'
			position: 'Salarie'
			gross_amount: p.gross_amount
			total_taxes: p.total_taxes
			net_amount: p.net_amount
			is_paid: p.is_paid
		}

		total_gross += p.gross_amount
		total_taxes += p.total_taxes
		total_net += p.net_amount
	}

	return dto.PayrollBookResponse{
		month: month
		year: year
		total_employees: items.len
		total_gross: total_gross
		total_taxes: total_taxes
		total_net: total_net
		items: items
	}
}