module repository

import db.pg
import models
import time

// ==================== PAYSLIPS ====================
pub fn (r &Repository) get_payslips_by_employee(emp_id int, org_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where employee_id == emp_id && organization_id == org_id order by id desc
	} or { [] }
}

pub fn (r &Repository) get_payslip_by_id(payslip_id int, org_id int) ?models.Payslip {
	result := sql r.db {
		select from models.Payslip where id == payslip_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

// get_payslips_by_employee_period retourne les bulletins d'un employé pour un mois/année (ESS).
pub fn (r &Repository) get_payslips_by_employee_period(emp_id int, month int, year int, org_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where employee_id == emp_id && period_start >= start_of_month(month, year) && period_start <= end_of_month(month, year) && organization_id == org_id order by id desc
	} or { [] }
}

// get_payslip_by_employee_period_id retourne un bulletin précis d'un employé (vérif propriétaire ESS).
pub fn (r &Repository) get_payslip_by_employee_period_id(emp_id int, payslip_id int, org_id int) ?models.Payslip {
	result := sql r.db {
		select from models.Payslip where id == payslip_id && employee_id == emp_id && organization_id == org_id limit 1
	} or { return none }
	if result.len == 0 {
		return none
	}
	return result[0]
}

pub fn (mut r Repository) create_payslip(payslip models.Payslip) !int {
	inserted_id := r.insert_id(fn [payslip] (mut tx pg.Tx) !int {
		return sql tx {
			insert payslip into models.Payslip
		}!
	})!
	return inserted_id
}

// create_payslips enregistre un lot de bulletins sans détail de retenues.
pub fn (mut r Repository) create_payslips(payslips []models.Payslip) ![]models.Payslip {
	return r.create_payslips_with_lines(payslips, [][]models.PayslipLine{})
}

// create_payslips_with_lines enregistre un lot de bulletins et leurs lignes de
// retenues de façon atomique (une seule transaction sur une connexion réservée) :
// soit tout est inséré, soit rien. lines[i] (si présent) est le détail de payslips[i].
// Retourne les bulletins avec leur id.
pub fn (mut r Repository) create_payslips_with_lines(payslips []models.Payslip, lines [][]models.PayslipLine) ![]models.Payslip {
	mut tx := r.begin()!
	mut saved := []models.Payslip{cap: payslips.len}
	for i, payslip in payslips {
		id := sql tx {
			insert payslip into models.Payslip
		} or {
			tx.rollback() or {}
			return error('Erreur lors de la sauvegarde du bulletin pour employé ${payslip.employee_id}: ${err}')
		}
		if i < lines.len {
			insert_lines(mut tx, id, payslip.organization_id, lines[i]) or {
				tx.rollback() or {}
				return error('Erreur lors de la sauvegarde du détail du bulletin pour employé ${payslip.employee_id}: ${err}')
			}
		}
		saved << models.Payslip{
			...payslip
			id: id
		}
	}
	tx.commit()!
	return saved
}

fn insert_lines(mut tx pg.Tx, payslip_id int, org_id int, lines []models.PayslipLine) ! {
	for line in lines {
		row := models.PayslipLine{
			...line
			payslip_id: payslip_id
			organization_id: org_id
		}
		sql tx {
			insert row into models.PayslipLine
		}!
	}
}

// get_payslip_lines retourne le détail figé d'un bulletin (vide pour un bulletin
// généré avant la migration 018).
pub fn (r &Repository) get_payslip_lines(payslip_id int, org_id int) []models.PayslipLine {
	return sql r.db {
		select from models.PayslipLine where payslip_id == payslip_id && organization_id == org_id order by position asc
	} or { [] }
}

// replace_payslip_calculation remplace les montants et le détail d'un bulletin
// recalculé. Uniquement en brouillon : la condition est vérifiée dans la requête
// elle-même, donc un bulletin soumis entre-temps n'est pas modifié. Le PDF en
// cache est invalidé (pdf_path vidé).
pub fn (mut r Repository) replace_payslip_calculation(p models.Payslip, lines []models.PayslipLine) ! {
	mut tx := r.begin()!
	replace_in_tx(mut tx, p, lines) or {
		tx.rollback() or {}
		return err
	}
	tx.commit()!
}

fn replace_in_tx(mut tx pg.Tx, p models.Payslip, lines []models.PayslipLine) ! {
	updated := tx.exec_param_many("UPDATE payslip SET gross_amount = \$3, total_taxes = \$4, net_amount = \$5, pdf_path = '' WHERE id = \$1 AND organization_id = \$2 AND status = 'brouillon' RETURNING id",
		[p.id.str(), p.organization_id.str(), p.gross_amount.str(), p.total_taxes.str(),
		p.net_amount.str()])!
	if updated.len == 0 {
		return error("Seul un bulletin 'brouillon' peut être recalculé")
	}
	tx.exec_param_many('DELETE FROM payslip_line WHERE payslip_id = \$1 AND organization_id = \$2',
		[p.id.str(), p.organization_id.str()])!
	insert_lines(mut tx, p.id, p.organization_id, lines)!
}

pub fn (mut r Repository) mark_payslip_paid(payslip_id int, org_id int) ! {
	sql r.db {
		update models.Payslip set is_paid = true, paid_at = time.now(), status = 'paye' where id == payslip_id && organization_id == org_id
	}!
}

// update_payslip_status change le statut du workflow d'un bulletin.
pub fn (mut r Repository) update_payslip_status(payslip_id int, new_status string, org_id int) ! {
	sql r.db {
		update models.Payslip set status = new_status where id == payslip_id && organization_id == org_id
	}!
}

// approve_payslip approuve un bulletin (statut + approbateur + horodatage).
pub fn (mut r Repository) approve_payslip(payslip_id int, approver string, org_id int) ! {
	sql r.db {
		update models.Payslip set status = 'approuve', approved_by = approver, approved_at = time.now() where id == payslip_id && organization_id == org_id
	}!
}

// get_all_payslips récupère la liste de tous les bulletins de paie d'une organisation
pub fn (r &Repository) get_all_payslips(org_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where organization_id == org_id order by id asc
	} or { [] }
}

// exists_payslip_for_period vérifie si des bulletins existent déjà pour un mois/année donné.
pub fn (r &Repository) exists_payslip_for_period(month int, year int, org_id int) bool {
	start := start_of_month(month, year)
	end := end_of_month(month, year)
	result := sql r.db {
		select from models.Payslip where period_start >= start && period_start <= end && organization_id == org_id limit 1
	} or { [] }
	return result.len > 0
}

// update_payslip_pdf_path enregistre le chemin du PDF généré sur le bulletin.
pub fn (mut r Repository) update_payslip_pdf_path(payslip_id int, path string, org_id int) ! {
	sql r.db {
		update models.Payslip set pdf_path = path where id == payslip_id && organization_id == org_id
	}!
}

// get_payslips_by_period retourne les bulletins d'un mois/année donné (filtrage SQL).
// Utilisé pour le Livre de Paie sans charger toute la table en mémoire.
pub fn (r &Repository) get_payslips_by_period(month int, year int, org_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where period_start >= start_of_month(month, year) && period_start <= end_of_month(month, year) && organization_id == org_id order by id asc
	} or { [] }
}

fn start_of_month(month int, year int) time.Time {
	return time.Time{ year: year, month: month, day: 1 }
}

fn end_of_month(month int, year int) time.Time {
	next_month := if month == 12 { 1 } else { month + 1 }
	next_year := if month == 12 { year + 1 } else { year }
	return time.Time{ year: next_year, month: next_month, day: 1 }.add_seconds(-1)
}