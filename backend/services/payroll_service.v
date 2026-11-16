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
	idx      int
	result   core.CalculationResult
	employer []core.TaxLine // cotisations patronales (figées avec le bulletin)
}

// compute_payslip calcule un bulletin (fonction pure) : résultat salarial et
// cotisations patronales, à partir des règles déjà sélectionnées pour la période.
fn compute_payslip(contract models.Contract, adjustments []models.Adjustment, tax_parts f32, use_config bool, eff_components []models.TaxComponent, eff_brackets []models.TaxBracket, rules []models.TaxRule) (core.CalculationResult, []core.TaxLine) {
	if use_config {
		result := core.compute_payslip_configurable(contract, eff_components, eff_brackets,
			adjustments, tax_parts)
		employer, _ := core.employer_contributions_configurable(eff_components, result.gross_pay)
		return result, employer
	}
	result := core.calculate_pay_full_ci(contract, rules, adjustments, tax_parts)
	employer, _ := core.calculate_employer_contributions_ci(rules, result.gross_pay)
	return result, employer
}

// payslip_lines convertit le détail d'un calcul en lignes figées du bulletin
// (retenues salariales puis cotisations patronales, dans l'ordre du calcul).
pub fn payslip_lines(salarial []core.TaxLine, patronal []core.TaxLine) []models.PayslipLine {
	mut lines := []models.PayslipLine{cap: salarial.len + patronal.len}
	for group in [salarial, patronal] {
		for t in group {
			lines << models.PayslipLine{
				position: lines.len + 1
				code: t.code
				label: t.name
				share: if t.share.len > 0 { t.share } else { core.share_salarial }
				base: t.base
				rate: t.rate
				amount: t.amount
			}
		}
	}
	return lines
}

// lines_to_tax_lines reconstitue le détail (salarial, patronal, total patronal)
// à partir des lignes figées, pour le PDF.
pub fn lines_to_tax_lines(lines []models.PayslipLine) ([]core.TaxLine, []core.TaxLine, i64) {
	mut sal := []core.TaxLine{}
	mut pat := []core.TaxLine{}
	mut pat_total := i64(0)
	for l in lines {
		t := core.TaxLine{
			name: l.label
			amount: l.amount
			code: l.code
			share: l.share
			base: l.base
			rate: l.rate
		}
		if l.share == core.share_patronal {
			pat << t
			pat_total += l.amount
		} else {
			sal << t
		}
	}
	return sal, pat, pat_total
}

// payout_worker calcule la paie d'un employé (fonction pure) et pousse le résultat
// dans le canal partagé. Eff_components/eff_brackets/rules sont en lecture seule,
// sélectionnées une seule fois dans `run_and_save_monthly_payroll`.
fn payout_worker(ch chan CalcOut, task EmpPayoutTask, use_config bool, eff_components []models.TaxComponent, eff_brackets []models.TaxBracket, rules []models.TaxRule) {
	result, employer := compute_payslip(task.contract, task.adjustments, task.tax_parts,
		use_config, eff_components, eff_brackets, rules)
	ch <- CalcOut{
		idx: task.idx
		result: result
		employer: employer
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
		return error('La paie de ${month}/${year} a déjà été générée. Pour corriger un bulletin en brouillon, utilisez le recalcul (POST /payslips/:id/recalculate).')
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
	mut employer_lines := [][]core.TaxLine{len: tasks.len}
	for _ in 0 .. tasks.len {
		out := <-ch
		results[out.idx] = out.result
		employer_lines[out.idx] = out.employer
	}
	if progress != unsafe { nil } {
		progress(60)
	}

	// 4. Construire les bulletins à partir des résultats
	mut payslips := []models.Payslip{}
	mut lines := [][]models.PayslipLine{cap: tasks.len}
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
		lines << payslip_lines(result.tax_details, employer_lines[i])
	}

	// 5-6. Enregistrement atomique du lot : une seule transaction sur une connexion
	// réservée — en cas d'échec d'un bulletin, aucun n'est conservé.
	saved := s.repo.create_payslips_with_lines(payslips, lines)!

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

// recalculate_payslip recalcule un bulletin en brouillon (ex: prime saisie après la
// génération, contrat corrigé, bulletin rejeté) avec le contrat actif, les ajustements
// du mois et les règles en vigueur à la période. Montants et détail sont remplacés
// dans une transaction ; le PDF en cache est invalidé. Retourne le bulletin à jour
// et son ancien net.
pub fn (mut s PayrollService) recalculate_payslip(org_id int, payslip_id int) !(models.Payslip, i64) {
	p := s.repo.get_payslip_by_id(payslip_id, org_id) or {
		return error('Bulletin ${payslip_id} introuvable')
	}
	if p.status != models.status_brouillon {
		return error("Seul un bulletin 'brouillon' peut être recalculé (statut actuel: '${p.status}')")
	}
	emp := s.repo.get_employee_by_id(p.employee_id, org_id) or {
		return error('Employé ${p.employee_id} introuvable')
	}
	contract := s.repo.get_active_contract(emp.id, org_id) or {
		return error('Aucun contrat actif pour ${emp.first_name} ${emp.last_name}')
	}
	month := p.period_start.month
	year := p.period_start.year
	period_date := '${year:04d}-${month:02d}-01'
	rules := s.repo.get_tax_rules('CI', org_id)
	components := s.repo.get_components(org_id)
	use_config := components.len > 0
	eff_components := if use_config {
		core.select_effective_components(components, period_date)
	} else {
		[]models.TaxComponent{}
	}
	eff_brackets := if use_config {
		core.select_effective_brackets(s.repo.get_brackets(org_id), period_date)
	} else {
		[]models.TaxBracket{}
	}
	adjustments := s.repo.get_adjustments_for_period(emp.id, month, year, org_id)
	result, employer := compute_payslip(contract, adjustments, emp.tax_parts, use_config,
		eff_components, eff_brackets, rules)
	updated := models.Payslip{
		...p
		gross_amount: result.gross_pay
		total_taxes: result.total_taxes
		net_amount: result.net_pay
		pdf_path: ''
	}
	s.repo.replace_payslip_calculation(updated, payslip_lines(result.tax_details, employer))!
	log_info('Bulletin ${payslip_id} recalculé : net ${p.net_amount} → ${updated.net_amount}')
	return updated, p.net_amount
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