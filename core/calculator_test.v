module core

import models

// ─── Helpers ────────────────────────────────────────────────────────────────
fn make_contract(base_salary i64, hourly_rate i64) models.Contract {
	return models.Contract{
		employee_id: 1
		base_salary: base_salary
		hourly_rate: hourly_rate
		currency: 'XOF'
	}
}

fn make_employee_rule(name string, rate f64) models.TaxRule {
	return models.TaxRule{
		name: name
		rate: rate
		is_employer: false
		country: 'CI'
	}
}

fn make_employer_rule(name string, rate f64) models.TaxRule {
	return models.TaxRule{
		name: name
		rate: rate
		is_employer: true
		country: 'CI'
	}
}

fn make_adjustment(employee_id int, amount i64, desc string) models.Adjustment {
	return models.Adjustment{
		employee_id: employee_id
		month: 8
		year: 2026
		amount: amount
		description: desc
	}
}

// ─── calculate_tax_amount ────────────────────────────────────────────────────
fn test_calculate_tax_amount_simple_rate() {
	rule := make_employee_rule('CNPS Retraite', 0.0412)
	assert calculate_tax_amount(400_000, rule) == 16_480
}

fn test_calculate_tax_amount_fixed_amount() {
	// Forfait CMU : 1 000 FCFA, le taux est ignoré
	rule := models.TaxRule{
		name: 'CMU Salarie'
		rate: 0.0
		is_employer: false
		fixed_amount: 1_000
		country: 'CI'
	}
	assert calculate_tax_amount(400_000, rule) == 1_000
}

fn test_calculate_tax_amount_with_ceiling() {
	// Plafond CNPS Retraite : 3 375 000 FCFA
	rule := models.TaxRule{
		name: 'CNPS Retraite (part salariale)'
		rate: 0.063
		is_employer: false
		ceiling: 3_375_000
		country: 'CI'
	}
	expected := i64(3_375_000.0 * 0.063) // 212 625
	assert calculate_tax_amount(5_000_000, rule) == expected
	assert calculate_tax_amount(400_000, rule) == i64(400_000.0 * 0.063)
}

fn test_calculate_tax_amount_zero_base() {
	assert calculate_tax_amount(0, make_employee_rule('CNPS', 0.0412)) == 0
}

fn test_calculate_tax_amount_rounding() {
	// 123 456 × 0.0412 = 5 086.3872 → arrondi 5 086
	assert calculate_tax_amount(123_456, make_employee_rule('CNPS Retraite', 0.0412)) == 5_086
}

// ─── calculate_pay ───────────────────────────────────────────────────────────
fn test_calculate_pay_base_salary_only() {
	contract := make_contract(400_000, 2_500)
	result := calculate_pay(contract, []models.TaxRule{}, []models.Adjustment{})

	assert result.gross_pay == 400_000
	assert result.total_taxes == 0
	assert result.net_pay == 400_000
	assert result.tax_details.len == 0
}

fn test_calculate_pay_with_employee_tax_rule() {
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]

	result := calculate_pay(contract, rules, []models.Adjustment{})

	expected_tax := i64(400_000.0 * 0.0412) // 16 480
	assert result.gross_pay == 400_000
	assert result.total_taxes == expected_tax
	assert result.net_pay == 400_000 - expected_tax
	assert result.tax_details.len == 1
	assert result.tax_details[0].name == 'CNPS Retraite'
	assert result.tax_details[0].amount == expected_tax
}

fn test_calculate_pay_employer_rules_excluded_from_net() {
	// Les cotisations patronales ne doivent PAS être déduites du net salarié
	contract := make_contract(400_000, 2_500)
	rules := [
		make_employee_rule('CNPS Retraite', 0.0412),
		make_employer_rule('CNPS Prestations Familiales', 0.07),
	]

	result := calculate_pay(contract, rules, []models.Adjustment{})

	expected_employee_tax := i64(400_000.0 * 0.0412)
	assert result.total_taxes == expected_employee_tax
	assert result.net_pay == 400_000 - expected_employee_tax
	// Seule la règle salariale apparaît dans les détails
	assert result.tax_details.len == 1
}

fn test_calculate_pay_with_prime() {
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := [make_adjustment(1, 50_000, 'Prime de performance')]

	result := calculate_pay(contract, rules, adjustments)

	assert result.gross_pay == 450_000
	assert result.total_taxes == i64(450_000.0 * 0.0412)
	assert result.net_pay == 450_000 - result.total_taxes
}

fn test_calculate_pay_with_negative_adjustment() {
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := [make_adjustment(1, -20_000, 'Retenue absence')]

	result := calculate_pay(contract, rules, adjustments)

	expected_gross := 380_000
	assert result.gross_pay == expected_gross
	assert result.total_taxes == i64(380_000.0 * 0.0412)
	assert result.net_pay == expected_gross - result.total_taxes
}

fn test_calculate_pay_zero_salary() {
	contract := make_contract(0, 0)
	result := calculate_pay(contract, [make_employee_rule('CNPS Retraite', 0.0412)], []models.Adjustment{})

	assert result.gross_pay == 0
	assert result.total_taxes == 0
	assert result.net_pay == 0
}

// ─── calculate_overtime_ci ───────────────────────────────────────────────────
fn test_calculate_overtime_ci_first_bracket() {
	// 1 à 6h : majoration 15%
	assert calculate_overtime_ci(2_000, 4.0) == 9_200 // 4 × 2000 × 1.15
}

fn test_calculate_overtime_ci_second_bracket() {
	// 7 à 8h : majoration 50% au-delà de la 6e heure
	// 8h → (6 × 2000 × 1.15) + (2 × 2000 × 1.50) = 13 800 + 6 000 = 19 800
	assert calculate_overtime_ci(2_000, 8.0) == 19_800
}

fn test_calculate_overtime_ci_beyond_8h() {
	// Au-delà de 8h : majoration 50% (comme la 7e/8e heure)
	// 10h → (6 × 2500 × 1.15) + (2 × 2500 × 1.50) + (2 × 2500 × 1.50) = 17 250 + 7 500 + 7 500 = 32 250
	assert calculate_overtime_ci(2_500, 10.0) == 32_250
}

fn test_calculate_overtime_ci_zero() {
	assert calculate_overtime_ci(2_500, 0.0) == 0
	assert calculate_overtime_ci(0, 10.0) == 0
}

fn test_calculate_overtime_ci_fractional_hours() {
	// 2.5h supp à 4000 FCFA/h → 4 000 × 2.5 × 1.15 = 11 500
	assert calculate_overtime_ci(4_000, 2.5) == 11_500
}

// ─── Fiscalité ivoirienne (IS, CN, IGR) ──────────────────────────────────────
fn test_calculate_is_ci() {
	// IS = 80% × Brut × 1.2% = 400 000 × 0.0096 = 3 840
	assert calculate_is_ci(400_000) == 3_840
	assert calculate_is_ci(0) == 0
}

fn test_calculate_cn_ci() {
	// Base abattue 20% : 320 000
	// (130k-50k)*1.5% + (200k-130k)*5% + (320k-200k)*10% = 1 200 + 3 500 + 12 000 = 16 700
	assert calculate_cn_ci(400_000) == 16_700
	assert calculate_cn_ci(50_000) == 0 // base ≤ 50 000
	assert calculate_cn_ci(0) == 0
}

fn test_calculate_igr_ci_family_parts() {
	is_tax := calculate_is_ci(400_000)
	cn_tax := calculate_cn_ci(400_000)

	igr_single := calculate_igr_ci(400_000, is_tax, cn_tax, 1.0)
	igr_family := calculate_igr_ci(400_000, is_tax, cn_tax, 2.5)

	assert igr_single > 0
	assert igr_family < igr_single
}

fn test_calculate_igr_ci_zero_gross() {
	assert calculate_igr_ci(0, 0, 0, 1.0) == 0
}

// ─── calculate_pay_full_ci (intégration) ─────────────────────────────────────
fn test_calculate_pay_full_ci_integration() {
	contract := make_contract(400_000, 2_500)
	rules := [
		models.TaxRule{
			name: 'CNPS Retraite (part salariale)'
			rate: 0.063
			is_employer: false
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CMU Salarié'
			rate: 0.0
			is_employer: false
			fixed_amount: 1_000
			country: 'CI'
		},
	]

	result := calculate_pay_full_ci(contract, rules, []models.Adjustment{}, 1.0)

	assert result.gross_pay == 400_000
	assert result.tax_details.len == 5 // CNPS Retraite, CMU, IS, CN, IGR
	assert result.net_pay < 400_000
	assert result.total_taxes == (result.gross_pay - result.net_pay)
}

fn test_calculate_pay_full_ci_with_ceiling() {
	// Salaire élevé : l'assiette CNPS est plafonnée, la fiscalité DGI s'applique
	contract := make_contract(5_000_000, 25_000)
	rules := [
		models.TaxRule{
			name: 'CNPS Retraite (part salariale)'
			rate: 0.063
			is_employer: false
			ceiling: 3_375_000
			country: 'CI'
		},
	]

	result := calculate_pay_full_ci(contract, rules, []models.Adjustment{}, 1.0)

	cnps := i64(3_375_000.0 * 0.063) // 212 625
	mut found_cnps := false
	for line in result.tax_details {
		if line.name == 'CNPS Retraite (part salariale)' && line.amount == cnps {
			found_cnps = true
			break
		}
	}
	assert found_cnps
	assert result.gross_pay == 5_000_000
}

// ─── calculate_employer_contributions_ci ─────────────────────────────────────
fn test_calculate_employer_contributions_ci_basic() {
	// Règles CNPS CI réelles (barème patronal)
	rules := [
		models.TaxRule{
			name: 'CNPS Retraite (part patronale)'
			rate: 0.077
			is_employer: true
			ceiling: 3_375_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Prestations Familiales (part patronale)'
			rate: 0.0575
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Accident du Travail (part patronale)'
			rate: 0.02
			is_employer: true
			ceiling: 70_000
			country: 'CI'
		},
		models.TaxRule{
			name: 'CNPS Régime Complémentaire (part patronale)'
			rate: 0.012
			is_employer: true
			ceiling: 3_375_000
			country: 'CI'
		},
	]

	details, total := calculate_employer_contributions_ci(rules, 400_000)

	assert details.len == 4
	assert total == 41_025 // 30 800 + 4 025 + 1 400 + 4 800
	assert details[0].amount == 30_800 // 7.7% du brut non plafonné
	assert details[1].amount == 4_025 // 5.75% plafonné à 70 000
	assert details[2].amount == 1_400 // 2% plafonné à 70 000
	assert details[3].amount == 4_800 // 1.2%
}

fn test_calculate_employer_contributions_ci_ignores_salaried() {
	// Les règles salariales (is_employer == false) sont exclues
	rules := [
		make_employee_rule('CNPS Retraite', 0.063),
		make_employer_rule('CNPS Retraite (part patronale)', 0.077),
	]

	details, total := calculate_employer_contributions_ci(rules, 400_000)

	assert details.len == 1
	assert total == 30_800
	assert details[0].name == 'CNPS Retraite (part patronale)'
}

fn test_calculate_employer_contributions_ci_empty() {
	details, total := calculate_employer_contributions_ci([]models.TaxRule{}, 400_000)
	assert details.len == 0
	assert total == 0
}