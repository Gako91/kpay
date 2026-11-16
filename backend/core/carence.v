module core

import math
import time
import models

// ==================== CARENCE MALADIE ====================
//
// Les premiers jours d'un arrêt maladie (délai de carence, paramétré par
// organisation) ne sont pas rémunérés. Pour une période de paie, on compte les
// jours de carence qui tombent dans le mois, arrêt par arrêt (jours calendaires
// à partir de la date de début de chaque arrêt approuvé), puis on retient
// salaire de base / 30 par jour (salaire journalier conventionnel).

fn day_index(t time.Time) i64 {
	return time.Time{
		year: t.year
		month: t.month
		day: t.day
	}.unix() / 86400
}

// carence_days_in_month compte les jours de carence d'un salarié tombant dans le
// mois : pour chaque arrêt maladie approuvé, la fenêtre [début, début + carence - 1]
// est bornée par la fin de l'arrêt puis intersectée avec le mois.
pub fn carence_days_in_month(leaves []models.LeaveRequest, carence int, month int, year int) int {
	if carence <= 0 {
		return 0
	}
	m_start := day_index(time.Time{ year: year, month: month, day: 1 })
	m_end := day_index(time.Time{ year: year, month: month, day: days_in_month(month, year) })
	mut total := i64(0)
	for l in leaves {
		if l.leave_type != 'maladie' || l.status != 'approuve' {
			continue
		}
		start := day_index(l.start_date)
		leave_end := day_index(l.end_date)
		mut c_end := start + i64(carence) - 1
		if leave_end >= start && leave_end < c_end {
			c_end = leave_end
		}
		lo := if start > m_start { start } else { m_start }
		hi := if c_end < m_end { c_end } else { m_end }
		if hi >= lo {
			total += hi - lo + 1
		}
	}
	return int(total)
}

// carence_deduction retourne la retenue de carence (montant positif) : jours × base / 30.
pub fn carence_deduction(base_salary i64, days int) i64 {
	if days <= 0 || base_salary <= 0 {
		return 0
	}
	return i64(math.round(f64(base_salary) * f64(days) / 30.0))
}
