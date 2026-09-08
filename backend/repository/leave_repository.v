module repository

import models

// create_leave_request enregistre une nouvelle demande de congé.
// Le statut initial est 'en_attente' sauf indication contraire (ex: N+1 absent).
pub fn (mut r Repository) create_leave_request(req models.LeaveRequest) !models.LeaveRequest {
	mut entry := req
	status := if entry.status.len == 0 { 'en_attente' } else { entry.status }
	entry = models.LeaveRequest{
		...entry
		status: status
	}
	inserted_id := sql r.db {
		insert entry into models.LeaveRequest
	}!
	return models.LeaveRequest{
		...entry
		id: inserted_id
	}
}

// get_leave_request retourne une demande de congé scoped par organisation.
pub fn (r &Repository) get_leave_request(id int, org_id int) ?models.LeaveRequest {
	result := sql r.db {
		select from models.LeaveRequest where id == id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// get_leave_requests_by_employee récupère toutes les demandes d'un employé.
pub fn (r &Repository) get_leave_requests_by_employee(employee_id int, org_id int) ![]models.LeaveRequest {
	return sql r.db {
		select from models.LeaveRequest where employee_id == employee_id && organization_id == org_id order by id desc
	}!
}

// get_all_leave_requests récupère toutes les demandes de congé d'une organisation.
pub fn (r &Repository) get_all_leave_requests(org_id int) ![]models.LeaveRequest {
	return sql r.db {
		select from models.LeaveRequest where organization_id == org_id order by id desc
	}!
}

// get_leave_requests_for_manager récupère les demandes des employés dont le N+1
// est l'employé manager_emp_id (résolution en mémoire : volumes modestes).
pub fn (r &Repository) get_leave_requests_for_manager(manager_emp_id int, org_id int) ![]models.LeaveRequest {
	all := sql r.db {
		select from models.LeaveRequest where organization_id == org_id order by id desc
	}!
	emps := sql r.db {
		select from models.Employee where organization_id == org_id
	}!
	mut manager_of := map[int]int{}
	for e in emps {
		mid := e.manager_id or { 0 }
		if mid > 0 {
			manager_of[e.id] = mid
		}
	}
	mut out := []models.LeaveRequest{}
	for lr in all {
		if manager_of[lr.employee_id] == manager_emp_id {
			out << lr
		}
	}
	return out
}

// update_leave_status met à jour le statut d'une demande de congé (compatibilité /
// décision RH directe). Enregistre le réviseur.
pub fn (mut r Repository) update_leave_status(id int, status string, approved_by string, org_id int) ! {
	sql r.db {
		update models.LeaveRequest set status = status, approved_by = approved_by where id == id && organization_id == org_id
	}!
}

// set_leave_justificatif enregistre le chemin MinIO du justificatif (maladie).
pub fn (mut r Repository) set_leave_justificatif(id int, org_id int, path string) ! {
	sql r.db {
		update models.LeaveRequest set justificatif_path = path where id == id && organization_id == org_id
	}!
}

// ==================== WORKFLOW 2 NIVEAUX ====================
// Chaque transition vérifie le statut courant dans la clause WHERE (anti-race) et
// RETURNING id pour détecter les transitions non autorisées (reste 0 si rien n'a changé).

// mark_mgr_approved : en_attente → valide_mgr (validation N+1).
pub fn (mut r Repository) mark_mgr_approved(id int, org_id int, approver string) !int {
	res := r.db.exec_param_many("UPDATE leaverequest SET status = 'valide_mgr', approved_by_mgr = \$3, approved_at_mgr = NOW() WHERE id = \$1 AND organization_id = \$2 AND status = 'en_attente' RETURNING id", [
		id.str(),
		org_id.str(),
		approver,
	]) or {
		return error('Erreur validation N+1: ${err}')
	}
	return res.len
}

// mark_mgr_rejected : en_attente → refuse (refus au niveau N+1, motif obligatoire).
pub fn (mut r Repository) mark_mgr_rejected(id int, org_id int, approver string, reason string) !int {
	res := r.db.exec_param_many("UPDATE leaverequest SET status = 'refuse', approved_by_mgr = \$3, rejection_reason = \$4 WHERE id = \$1 AND organization_id = \$2 AND status = 'en_attente' RETURNING id", [
		id.str(),
		org_id.str(),
		approver,
		reason,
	]) or {
		return error('Erreur refus N+1: ${err}')
	}
	return res.len
}

// mark_rh_approved : en_attente|valide_mgr → approuve (validation RH, finale).
pub fn (mut r Repository) mark_rh_approved(id int, org_id int, approver string) !int {
	res := r.db.exec_param_many("UPDATE leaverequest SET status = 'approuve', approved_by = \$3, approved_at = NOW() WHERE id = \$1 AND organization_id = \$2 AND status IN ('en_attente', 'valide_mgr') RETURNING id", [
		id.str(),
		org_id.str(),
		approver,
	]) or {
		return error('Erreur validation RH: ${err}')
	}
	return res.len
}

// mark_rh_rejected : en_attente|valide_mgr → refuse (refus au niveau RH, motif obligatoire).
pub fn (mut r Repository) mark_rh_rejected(id int, org_id int, approver string, reason string) !int {
	res := r.db.exec_param_many("UPDATE leaverequest SET status = 'refuse', approved_by = \$3, rejection_reason = \$4 WHERE id = \$1 AND organization_id = \$2 AND status IN ('en_attente', 'valide_mgr') RETURNING id", [
		id.str(),
		org_id.str(),
		approver,
		reason,
	]) or {
		return error('Erreur refus RH: ${err}')
	}
	return res.len
}