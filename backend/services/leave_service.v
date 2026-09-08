module services

import time
import models
import repository

// Types de congés acceptés et cumul mensuel pour les soldes annuels.
const leave_allowed_types = ['conge_paye', 'rtt', 'maladie', 'sans_solde']

// Congé payé : 2,08 j/mois (≈ 25 jours/an, régime courant) ; RTT : 1 j/mois (12/an).
const leave_accrual_per_type = {
	'conge_paye': f32(2.08)
	'rtt':        f32(1.0)
}

// LeaveService orchestre le workflow congés 2 niveaux (N+1 → RH), les soldes
// annuels (cumul + déduction à la validation RH) et les notifications.
pub struct LeaveService {
mut:
	repo   repository.Repository
	mailer MailerService
}

pub fn new_leave_service(mut repo repository.Repository) LeaveService {
	return LeaveService{
		repo: repo
		mailer: MailerService{}
	}
}

pub fn (mut s LeaveService) set_mailer(m MailerService) {
	s.mailer = m
}

// notify journalise et envoie (si SMTP configuré) une notification à un employé.
fn (s &LeaveService) notify(emp models.Employee, subject string, message string) {
	if s.mailer.enabled && emp.email.len > 0 {
		s.mailer.send(emp.email, subject, message) or {
			log_warn('Échec envoi email ${emp.email}: ${err}')
		}
	}
	log_info('Notification congés -> ${emp.email}: ${subject}')
}

// resolve_initial_status détermine l'étape initiale du workflow :
// - un manager actif est rattaché → en_attente (validation N+1 d'abord)
// - sinon → valide_mgr (N+1 automatiquement passé : décision RH directe)
fn (s &LeaveService) resolve_initial_status(emp models.Employee, org_id int) string {
	manager_id := emp.manager_id or { 0 }
	if manager_id > 0 {
		mgr := s.repo.get_employee_by_id(manager_id, org_id) or { return 'valide_mgr' }
		if mgr.is_active {
			return 'en_attente'
		}
	}
	return 'valide_mgr'
}

// submit_request crée une demande de congé pour l'employé et notifie le N+1.
pub fn (mut s LeaveService) submit_request(emp models.Employee, leave_type string, start time.Time, end time.Time, days f32, reason string, org_id int) !models.LeaveRequest {
	if !leave_allowed_types.contains(leave_type) {
		return error("Type de congé invalide: '${leave_type}'")
	}
	if end < start {
		return error('La date de fin doit être postérieure ou égale à la date de début')
	}
	if days <= 0 {
		return error('Le nombre de jours doit être positif')
	}
	req := models.LeaveRequest{
		organization_id: org_id
		employee_id: emp.id
		leave_type: leave_type
		start_date: start
		end_date: end
		days_count: days
		reason: reason
		status: s.resolve_initial_status(emp, org_id)
	}
	created := s.repo.create_leave_request(req)!

	period := '${start.format()} au ${end.format()}'
	if created.status == 'en_attente' {
		manager_id := emp.manager_id or { 0 }
		mgr := s.repo.get_employee_by_id(manager_id, org_id) or { return created }
		s.notify(mgr, 'Nouvelle demande de congé à valider', 'Votre collaborateur ${emp.first_name} ${emp.last_name} a soumis une demande de ${leave_type} du ${period} (${days} j).')
	}
	s.notify(emp, 'Demande de congé soumise', 'Votre demande de ${leave_type} du ${period} est en cours de traitement.')
	return created
}

// ==================== VALIDATION N+1 ====================

// mgr_approve valide au niveau N+1 (le droit est contrôlé côté route : manager du
// demandeur ou décideur RH). Transition en_attente → valide_mgr.
pub fn (mut s LeaveService) mgr_approve(leave_id int, org_id int, actor string) !models.LeaveRequest {
	lr := s.repo.get_leave_request(leave_id, org_id) or { return error('Demande de congé introuvable') }
	if lr.status != 'en_attente' {
		return error("La demande n'est pas en attente de validation N+1 (statut: '${lr.status}')")
	}
	changed := s.repo.mark_mgr_approved(leave_id, org_id, actor)!
	if changed == 0 {
		return error('Transition impossible (état concurrent)')
	}
	updated := s.repo.get_leave_request(leave_id, org_id) or { return lr }
	requester := s.repo.get_employee_by_id(lr.employee_id, org_id) or { return updated }
	s.notify(requester, 'Demande de congé validée par votre N+1', 'Votre demande de ${lr.leave_type} (${lr.days_count} j) a été validée par votre manager. Elle est en attente de validation RH.')
	return updated
}

// mgr_reject refuse au niveau N+1 (motif obligatoire). en_attente → refuse.
pub fn (mut s LeaveService) mgr_reject(leave_id int, org_id int, actor string, reason string) !models.LeaveRequest {
	if reason.trim_space().len == 0 {
		return error('Un motif de refus est obligatoire')
	}
	lr := s.repo.get_leave_request(leave_id, org_id) or { return error('Demande de congé introuvable') }
	if lr.status != 'en_attente' {
		return error("La demande n'est pas en attente de validation N+1 (statut: '${lr.status}')")
	}
	changed := s.repo.mark_mgr_rejected(leave_id, org_id, actor, reason)!
	if changed == 0 {
		return error('Transition impossible (état concurrent)')
	}
	requester := s.repo.get_employee_by_id(lr.employee_id, org_id) or { return lr }
	s.notify(requester, 'Demande de congé refusée', "Votre demande de ${lr.leave_type} (${lr.days_count} j) a été refusée par votre manager. Motif: ${reason}")
	return s.repo.get_leave_request(leave_id, org_id) or { return lr }
}

// ==================== VALIDATION RH ====================

// rh_approve valide définitivement une demande (en_attente ou valide_mgr).
// Débite le solde annuel de l'employé (hors congé maladie), puis notifie.
pub fn (mut s LeaveService) rh_approve(leave_id int, org_id int, actor string) !models.LeaveRequest {
	lr := s.repo.get_leave_request(leave_id, org_id) or { return error('Demande de congé introuvable') }
	if lr.status != 'en_attente' && lr.status != 'valide_mgr' {
		return error("La demande n'est pas en attente de validation RH (statut: '${lr.status}')")
	}
	changed := s.repo.mark_rh_approved(leave_id, org_id, actor)!
	if changed == 0 {
		return error('Transition impossible (état concurrent)')
	}

	if lr.leave_type != 'maladie' {
		emp := s.repo.get_employee_by_id(lr.employee_id, org_id) or { return lr }
		s.ensure_year_balance(emp, lr.start_date.year, org_id) or {
			log_warn('Cumul de solde impossible pour employé ${emp.id}: ${err}')
		}
		bal := s.repo.get_leave_balance(lr.employee_id, lr.start_date.year, lr.leave_type, org_id) or {
			models.LeaveBalance{}
		}
		if bal.id > 0 {
			s.repo.add_used_leave_days(bal.id, org_id, lr.days_count) or {
				log_warn("Débit du solde impossible (demande ${lr.id}): ${err}")
			}
		}
	}

	updated := s.repo.get_leave_request(leave_id, org_id) or { return lr }
	requester := s.repo.get_employee_by_id(lr.employee_id, org_id) or { return updated }
	s.notify(requester, 'Demande de congé approuvée (RH)', 'Votre demande de ${lr.leave_type} (${lr.days_count} j) a été approuvée. Bon congé !')
	return updated
}

// rh_reject refuse définitivement une demande (en_attente ou valide_mgr), motif obligatoire.
pub fn (mut s LeaveService) rh_reject(leave_id int, org_id int, actor string, reason string) !models.LeaveRequest {
	if reason.trim_space().len == 0 {
		return error('Un motif de refus est obligatoire')
	}
	lr := s.repo.get_leave_request(leave_id, org_id) or { return error('Demande de congé introuvable') }
	if lr.status != 'en_attente' && lr.status != 'valide_mgr' {
		return error("La demande n'est pas en attente de validation RH (statut: '${lr.status}')")
	}
	changed := s.repo.mark_rh_rejected(leave_id, org_id, actor, reason)!
	if changed == 0 {
		return error('Transition impossible (état concurrent)')
	}
	requester := s.repo.get_employee_by_id(lr.employee_id, org_id) or { return lr }
	s.notify(requester, 'Demande de congé refusée (RH)', "Votre demande de ${lr.leave_type} (${lr.days_count} j) a été refusée. Motif: ${reason}")
	return s.repo.get_leave_request(leave_id, org_id) or {
		return lr
	}
}

// ==================== SOLDES ANNUELS ====================

// get_balance garantit le cumul de l'année puis retourne les soldes de l'employé.
pub fn (mut s LeaveService) get_balance(emp models.Employee, year int, org_id int) ![]models.LeaveBalance {
	s.ensure_year_balance(emp, year, org_id)!
	return s.repo.get_leave_balances(emp.id, year, org_id)
}

// ensure_year_balance crée les lignes de solde manquantes d'une année avec le cumul
// acquis (idempotent : les lignes existantes ne sont jamais recréées ni recumulées).
fn (mut s LeaveService) ensure_year_balance(emp models.Employee, year int, org_id int) ! {
	months := s.hire_months(emp.id, org_id, year)
	for t in leave_allowed_types {
		exists := s.repo.get_leave_balance(emp.id, year, t, org_id)
		if exists != none {
			continue
		}
		accrued := if t in leave_accrual_per_type {
			leave_accrual_per_type[t] * months
		} else {
			f32(0)
		}
		s.repo.create_leave_balance(models.LeaveBalance{
			organization_id: org_id
			employee_id: emp.id
			year: year
			leave_type: t
			accrued_days: accrued
			used_days: 0
		})!
	}
}

// hire_months évalue le nombre de mois crédités dans l'année courante :
// - embauche dans l'année (contrat actif) → mois restants à compter de l'embauche
// - sinon → année complète (12 mois)
fn (s &LeaveService) hire_months(emp_id int, org_id int, year int) f32 {
	contract := s.repo.get_active_contract(emp_id, org_id) or { return f32(12) }
	start := contract.start_date
	if start.year == year {
		months := 12 - int(start.month) + 1
		if months < 1 {
			return f32(12)
		}
		return f32(months)
	}
	return f32(12)
}