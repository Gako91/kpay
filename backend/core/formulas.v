module core

// Calcul du prorata pour les entrées/sorties en cours de mois
pub fn calculate_prorata(base_salary i64, start_day int, end_day int, days_in_month int) i64 {
	worked_days := end_day - start_day + 1
	return i64(f64(base_salary) * f64(worked_days) / f64(days_in_month))
}

// Calcul des congés payés acquis (2.5 jours par mois)
pub fn calculate_vacation_days(months_worked int) f64 {
	return f64(months_worked) * 2.5
}

// Calcul de l'indemnité de congés payés
pub fn calculate_vacation_pay(daily_salary i64, days int) i64 {
	return daily_salary * i64(days)
}

// Calcul du salaire journalier
pub fn calculate_daily_salary(monthly_salary i64) i64 {
	return i64(f64(monthly_salary) / 21.67)
}

// Nombre de jours dans un mois
pub fn days_in_month(month int, year int) int {
	if month in [1, 3, 5, 7, 8, 10, 12] {
		return 31
	} else if month in [4, 6, 9, 11] {
		return 30
	} else {
		if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
			return 29
		}
		return 28
	}
}
