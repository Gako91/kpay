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

// ─── calculate_pay ───────────────────────────────────────────────────────────
fn test_calculate_pay_base_salary_only() {
	contract := make_contract(400_000, 2_500)
	rules := []models.TaxRule{}
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	assert result.gross_pay == 400_000
	assert result.total_taxes == 0
	assert result.net_pay == 400_000
	assert result.tax_details.len == 0
}

fn test_calculate_pay_with_employee_tax_rule() {
	// Taux salarial CNPS Retraite : 4.12 % sur brut de 400 000
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	expected_tax := i64(f64(400_000) * 0.0412) // 16 480
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
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	expected_employee_tax := i64(f64(400_000) * 0.0412)
	assert result.total_taxes == expected_employee_tax
	assert result.net_pay == 400_000 - expected_employee_tax
	// Seule la règle salariale apparaît dans les détails
	assert result.tax_details.len == 1
}

fn test_calculate_pay_multiple_employee_rules() {
	// CNPS CI complet : Retraite 4.12% + Maladie-Maternité 0.75%
	contract := make_contract(500_000, 3_000)
	rules := [
		make_employee_rule('CNPS Retraite', 0.0412),
		make_employee_rule('CNPS Maladie-Maternité', 0.0075),
	]
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	tax_retraite := i64(f64(500_000) * 0.0412)
	tax_maladie := i64(f64(500_000) * 0.0075)
	assert result.total_taxes == tax_retraite + tax_maladie
	assert result.net_pay == 500_000 - (tax_retraite + tax_maladie)
	assert result.tax_details.len == 2
}

fn test_calculate_pay_with_prime() {
	// Prime de 50 000 s'ajoute au brut avant le calcul des taxes
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := [make_adjustment(1, 50_000, 'Prime de performance')]

	result := calculate_pay(contract, rules, adjustments)

	expected_gross := 450_000
	expected_tax := i64(f64(expected_gross) * 0.0412)
	assert result.gross_pay == expected_gross
	assert result.total_taxes == expected_tax
	assert result.net_pay == expected_gross - expected_tax
}

fn test_calculate_pay_with_negative_adjustment() {
	// Retenue (montant négatif) réduit le brut
	contract := make_contract(400_000, 2_500)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := [make_adjustment(1, -20_000, 'Retenue absence')]

	result := calculate_pay(contract, rules, adjustments)

	expected_gross := 380_000
	expected_tax := i64(f64(expected_gross) * 0.0412)
	assert result.gross_pay == expected_gross
	assert result.total_taxes == expected_tax
	assert result.net_pay == expected_gross - expected_tax
}

fn test_calculate_pay_multiple_adjustments() {
	// Plusieurs ajustements cumulés
	contract := make_contract(400_000, 2_500)
	rules := []models.TaxRule{}
	adjustments := [
		make_adjustment(1, 30_000, 'Prime ancienneté'),
		make_adjustment(1, 20_000, 'Prime transport'),
		make_adjustment(1, -10_000, 'Retenue avance'),
	]

	result := calculate_pay(contract, rules, adjustments)

	assert result.gross_pay == 440_000 // 400k + 30k + 20k - 10k
	

	assert result.total_taxes == 0
	assert result.net_pay == 440_000
}

fn test_calculate_pay_zero_salary() {
	contract := make_contract(0, 0)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	assert result.gross_pay == 0
	assert result.total_taxes == 0
	assert result.net_pay == 0
}

// ─── calculate_overtime ──────────────────────────────────────────────────────
fn test_calculate_overtime_standard() {
	// 10h supp à 2500 FCFA/h → 2500 × 10 × 1.25 = 31 250
	result := calculate_overtime(2_500, 10.0)
	assert result == 31_250
}

fn test_calculate_overtime_zero_hours() {
	result := calculate_overtime(2_500, 0.0)
	assert result == 0
}

fn test_calculate_overtime_zero_rate() {
	result := calculate_overtime(0, 10.0)
	assert result == 0
}

fn test_calculate_overtime_fractional_hours() {
	// 2.5h supp à 4000 FCFA/h → 4000 × 2.5 × 1.25 = 12 500
	result := calculate_overtime(4_000, 2.5)
	assert result == 12_500
}

fn test_calculate_overtime_multiplier_is_125_percent() {
	// Vérification que la majoration est bien 25% (et non 50%)
	result_normal := calculate_overtime(1_000, 1.0) // sans majoration : 1000
	result_overtime := calculate_overtime(1_000, 1.0) // avec 25% : 1250
	assert result_overtime == 1_250
	// result_normal et result_overtime sont identiques ici — on vérifie la valeur absolue
	assert result_normal == 1_250
}

// ─── apply_tax_rules ─────────────────────────────────────────────────────────
fn test_apply_tax_rules_employee_part() {
	rules := [
		make_employee_rule('CNPS Retraite', 0.0412),
		make_employer_rule('CNPS Prestations Familiales', 0.07),
	]
	// employer_part = false → on calcule la part salariale uniquement
	tax := apply_tax_rules(400_000, rules, false)
	assert tax == i64(f64(400_000) * 0.0412)
}

fn test_apply_tax_rules_employer_part() {
	rules := [
		make_employee_rule('CNPS Retraite', 0.0412),
		make_employer_rule('CNPS Prestations Familiales', 0.07),
		make_employer_rule('CNPS AMV', 0.026),
	]
	// employer_part = true → seulement les deux règles patronales
	tax := apply_tax_rules(400_000, rules, true)
	expected := i64(f64(400_000) * 0.07) + i64(f64(400_000) * 0.026)
	assert tax == expected
}

fn test_apply_tax_rules_empty_rules() {
	tax := apply_tax_rules(400_000, []models.TaxRule{}, false)
	assert tax == 0
}

fn test_apply_tax_rules_zero_gross() {
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	tax := apply_tax_rules(0, rules, false)
	assert tax == 0
}

// ─── Tests Plafonnement CNPS et CMU CI ───────────────────────────────────────
fn test_calculate_pay_with_ceiling_cnps_retraite() {
	// Cadre avec salaire de 5 000 000 FCFA (> plafond CNPS Retraite de 3 375 000 FCFA)
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
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	// L'assiette doit être plafonnée à 3 375 000 FCFA
	expected_tax := i64(3_375_000.0 * 0.063) // 212 625 FCFA
	assert result.gross_pay == 5_000_000
	assert result.total_taxes == expected_tax
	assert result.net_pay == 5_000_000 - expected_tax
	assert result.tax_details[0].amount == expected_tax
}

fn test_calculate_pay_with_fixed_amount_cmu() {
	// Forfait CMU : 1 000 FCFA
	contract := make_contract(400_000, 2_500)
	rules := [
		models.TaxRule{
			name: 'CMU Salarié'
			rate: 0.0
			is_employer: false
			fixed_amount: 1_000
			country: 'CI'
		},
	]
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	assert result.total_taxes == 1_000
	assert result.net_pay == 399_000
}

fn test_calculate_overtime_ci_legal_brackets() {
	// 4h supp à 2000 FCFA/h -> 4 * 2000 * 1.15 = 9 200 FCFA
	assert calculate_overtime_ci(2_000, 4.0) == 9_200

	// 8h supp à 2000 FCFA/h -> (6 * 2000 * 1.15) + (2 * 2000 * 1.50) = 13 800 + 6 000 = 19 800 FCFA
	assert calculate_overtime_ci(2_000, 8.0) == 19_800
}

fn test_calculate_fiscalite_ivoirienne_is_cn_igr() {
	// Salaire brut : 400 000 FCFA, 1 part fiscale (célibataire sans enfant)
	// Base 80% = 320 000 FCFA
	// IS = 320 000 * 1.2% = 3 840 FCFA
	// CN = (130 000 - 50 000)*1.5% + (200 000 - 130 000)*5% + (320 000 - 200 000)*10% = 1200 + 3500 + 12000 = 16 700 FCFA
	is_tax := calculate_is_ci(400_000)
	assert is_tax == 3_840

	cn_tax := calculate_cn_ci(400_000)
	assert cn_tax == 16_700

	// IGR pour 1 part
	igr_tax := calculate_igr_ci(400_000, is_tax, cn_tax, 1.0)
	assert igr_tax > 0

	// IGR pour 2.5 parts doit être strictement inférieur à l'IGR pour 1 part
	igr_tax_family := calculate_igr_ci(400_000, is_tax, cn_tax, 2.5)
	assert igr_tax_family < igr_tax
}

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
	adjustments := []models.Adjustment{}

	result := calculate_pay_full_ci(contract, rules, adjustments, 1.0)

	assert result.gross_pay == 400_000
	assert result.tax_details.len == 5 // CNPS Retraite, CMU, IS, CN, IGR
	
	assert result.net_pay < 400_000
	assert result.total_taxes == (result.gross_pay - result.net_pay)
}

fn test_calculate_pay_rounding_precision() {
	// Exemple avec un montant qui génère une fraction décimale : 123 456 FCFA * 0.0412 = 5086.3872 -> arrondi à 5086
	contract := make_contract(123_456, 1_000)
	rules := [make_employee_rule('CNPS Retraite', 0.0412)]
	adjustments := []models.Adjustment{}

	result := calculate_pay(contract, rules, adjustments)

	assert result.total_taxes == 5086
	assert result.net_pay == 123_456 - 5086
}
