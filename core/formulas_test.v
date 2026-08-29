module core

// ─── days_in_month ───────────────────────────────────────────────────────────

fn test_days_in_month_31_days() {
	assert days_in_month(1, 2026) == 31  // Janvier
	assert days_in_month(3, 2026) == 31  // Mars
	assert days_in_month(5, 2026) == 31  // Mai
	assert days_in_month(7, 2026) == 31  // Juillet
	assert days_in_month(8, 2026) == 31  // Août
	assert days_in_month(10, 2026) == 31 // Octobre
	assert days_in_month(12, 2026) == 31 // Décembre
}

fn test_days_in_month_30_days() {
	assert days_in_month(4, 2026) == 30  // Avril
	assert days_in_month(6, 2026) == 30  // Juin
	assert days_in_month(9, 2026) == 30  // Septembre
	assert days_in_month(11, 2026) == 30 // Novembre
}

fn test_days_in_month_february_common_year() {
	assert days_in_month(2, 2026) == 28 // 2026 n'est pas bissextile
	assert days_in_month(2, 2023) == 28
	assert days_in_month(2, 1900) == 28 // Divisible par 100 mais pas 400
}

fn test_days_in_month_february_leap_year_div_4() {
	assert days_in_month(2, 2024) == 29 // Bissextile (div par 4, pas par 100)
	assert days_in_month(2, 2028) == 29
}

fn test_days_in_month_february_leap_year_div_400() {
	assert days_in_month(2, 2000) == 29 // Bissextile (div par 400)
}

fn test_days_in_month_february_not_leap_div_100() {
	assert days_in_month(2, 1900) == 28 // Div par 100 mais pas par 400 → pas bissextile
	assert days_in_month(2, 2100) == 28
}

// ─── calculate_prorata ───────────────────────────────────────────────────────

fn test_calculate_prorata_full_month() {
	// Travaillé du 1er au 30 → 30/30 = salaire complet
	result := calculate_prorata(300_000, 1, 30, 30)
	assert result == 300_000
}

fn test_calculate_prorata_half_month() {
	// Travaillé du 1er au 15 dans un mois de 30 → 15/30 = 50%
	result := calculate_prorata(300_000, 1, 15, 30)
	assert result == 150_000
}

fn test_calculate_prorata_one_day() {
	result := calculate_prorata(310_000, 1, 1, 31)
	assert result == 10_000 // 1/31 ≈ 10 000
}

fn test_calculate_prorata_arrival_mid_month() {
	// Arrivée le 16 dans un mois de 31 jours → 16 jours travaillés (16-31)
	result := calculate_prorata(400_000, 16, 31, 31)
	assert result == i64(f64(400_000) * f64(16) / f64(31))
}

fn test_calculate_prorata_zero_salary() {
	result := calculate_prorata(0, 1, 30, 30)
	assert result == 0
}

// ─── calculate_vacation_days ─────────────────────────────────────────────────

fn test_calculate_vacation_days_one_month() {
	assert calculate_vacation_days(1) == 2.5
}

fn test_calculate_vacation_days_twelve_months() {
	assert calculate_vacation_days(12) == 30.0
}

fn test_calculate_vacation_days_zero_months() {
	assert calculate_vacation_days(0) == 0.0
}

fn test_calculate_vacation_days_partial() {
	// 5 mois → 12.5 jours
	assert calculate_vacation_days(5) == 12.5
}

// ─── calculate_vacation_pay ──────────────────────────────────────────────────

fn test_calculate_vacation_pay_standard() {
	// Salaire journalier 15 000, 10 jours de congé → 150 000
	assert calculate_vacation_pay(15_000, 10) == 150_000
}

fn test_calculate_vacation_pay_zero_days() {
	assert calculate_vacation_pay(15_000, 0) == 0
}

fn test_calculate_vacation_pay_zero_salary() {
	assert calculate_vacation_pay(0, 10) == 0
}

// ─── calculate_daily_salary ──────────────────────────────────────────────────

fn test_calculate_daily_salary_standard() {
	// 400 000 / 21.67 ≈ 18 465
	daily := calculate_daily_salary(400_000)
	assert daily == i64(f64(400_000) / 21.67)
}

fn test_calculate_daily_salary_round_value() {
	// 216 700 / 21.67 = 10 000 exactement
	daily := calculate_daily_salary(216_700)
	assert daily == 10_000
}

fn test_calculate_daily_salary_zero() {
	assert calculate_daily_salary(0) == 0
}

// ─── Cohérence inter-fonctions ───────────────────────────────────────────────

fn test_vacation_pay_pipeline() {
	// Scénario complet : 6 mois travaillés, salaire mensuel 300 000
	months := 6
	monthly := i64(300_000)

	days_acquired := calculate_vacation_days(months) // 15.0 jours
	daily := calculate_daily_salary(monthly)
	pay := calculate_vacation_pay(daily, int(days_acquired))

	assert days_acquired == 15.0
	assert daily == i64(f64(300_000) / 21.67)
	assert pay == daily * 15
}
