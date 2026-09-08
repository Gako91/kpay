module core

import models

fn test_component_amount_modes() {
	// forfait
	flat := models.TaxComponent{ code: 'CMU', name: 'CMU', rate: 0.0, basis_type: 'forfait', fixed_amount: 1000, share: 'salarial', is_active: true }
	assert component_amount(400_000, flat) == 1000
	// brut
	brut := models.TaxComponent{ code: 'IS2', name: 'IS', rate: 0.012, basis_type: 'brut', share: 'salarial', is_active: true }
	assert component_amount(400_000, brut) == 4800
	// brut80 (abattement 20%)
	brut80 := models.TaxComponent{ code: 'IS', name: 'IS', rate: 0.012, basis_type: 'brut80', share: 'salarial', is_active: true }
	assert component_amount(400_000, brut80) == 3840
	// plafonne
	capped := models.TaxComponent{ code: 'CNPS_RET', name: 'Retraite', rate: 0.063, basis_type: 'plafonne', cap: 3_375_000, share: 'salarial', is_active: true }
	assert component_amount(400_000, capped) == 25_200
	assert component_amount(5_000_000, capped) == 212_625 // 3 375 000 * 0.063
}

fn test_component_amount_zero_base() {
	brut := models.TaxComponent{ code: 'X', name: 'X', rate: 0.05, basis_type: 'brut', share: 'salarial', is_active: true }
	assert component_amount(0, brut) == 0
}

fn test_bracket_amount_cn() {
	brackets := [
		models.TaxBracket{ component_code: 'CN', lower_bound: 0, upper_bound: 50_000, rate: 0.0, flat: 0, is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 50_000, upper_bound: 130_000, rate: 0.015, flat: 750, is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 130_000, upper_bound: 200_000, rate: 0.05, flat: 5_300, is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 200_000, upper_bound: -1, rate: 0.10, flat: 15_300, is_active: true },
	]
	assert bracket_amount(320_000, brackets) == 16_700 // 320 000*0.10 - 15 300
	assert bracket_amount(80_000, brackets) == 450      // 80 000*0.015 - 750
	assert bracket_amount(40_000, brackets) == 0        // tranche à 0% (44100*0? non) 40000 < 50000 -> 0
	assert bracket_amount(170_000, brackets) == 3_200   // 170 000*0.05 - 5 300
}

fn test_bracket_amount_igr_formula() {
	brackets := [
		models.TaxBracket{ component_code: 'IGR', lower_bound: 220_583, upper_bound: 389_583, rate: 0.2592592593, flat: 24_306, is_active: true },
	]
	assert bracket_amount(300_000, brackets) == 53_472 // 300 000*0.259259... - 24 306 = 53 471.777 -> 53 472
}

fn test_engine_equals_legacy_ci() {
	components := [
		models.TaxComponent{ code: 'CNPS_RET', name: 'CNPS Retraite', rate: 0.063, basis_type: 'plafonne', cap: 3_375_000, share: 'salarial', effective_from: '2026-01-01', is_active: true, country: 'CI' },
		models.TaxComponent{ code: 'CMU', name: 'CMU Salarié', rate: 0.0, basis_type: 'forfait', fixed_amount: 1000, share: 'salarial', effective_from: '2026-01-01', is_active: true, country: 'CI' },
		models.TaxComponent{ code: 'IS', name: 'Impôt sur Salaire (IS)', rate: 0.012, basis_type: 'brut80', share: 'salarial', effective_from: '2026-01-01', is_active: true, country: 'CI' },
		models.TaxComponent{ code: 'CN', name: 'Contribution Nationale (CN)', rate: 0.0, basis_type: 'brut80', share: 'salarial', effective_from: '2026-01-01', is_active: true, country: 'CI' },
		models.TaxComponent{ code: 'IGR', name: 'Impôt Général Revenu (IGR)', rate: 0.0, basis_type: 'brut', share: 'salarial', effective_from: '2026-01-01', is_active: true, country: 'CI' },
	]
	brackets := [
		models.TaxBracket{ component_code: 'CN', lower_bound: 0, upper_bound: 50_000, rate: 0.0, flat: 0, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 50_000, upper_bound: 130_000, rate: 0.015, flat: 750, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 130_000, upper_bound: 200_000, rate: 0.05, flat: 5_300, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'CN', lower_bound: 200_000, upper_bound: -1, rate: 0.10, flat: 15_300, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 0, upper_bound: 25_000, rate: 0.0, flat: 0, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 25_000, upper_bound: 45_583, rate: 0.0909090909, flat: 2_273, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 45_583, upper_bound: 81_583, rate: 0.1304347826, flat: 4_076, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 81_583, upper_bound: 126_583, rate: 0.1666666667, flat: 7_031, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 126_583, upper_bound: 220_583, rate: 0.2, flat: 11_250, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 220_583, upper_bound: 389_583, rate: 0.2592592593, flat: 24_306, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 389_583, upper_bound: 842_666, rate: 0.3103448276, flat: 44_181, effective_from: '2026-01-01', is_active: true },
		models.TaxBracket{ component_code: 'IGR', lower_bound: 842_666, upper_bound: -1, rate: 0.375, flat: 98_633, effective_from: '2026-01-01', is_active: true },
	]
	legacy_rules := [
		models.TaxRule{ name: 'CNPS Retraite', rate: 0.063, is_employer: false, ceiling: 3_375_000 },
		models.TaxRule{ name: 'CMU', rate: 0.0, fixed_amount: 1_000, is_employer: false },
	]

	for gross in [i64(300_000), 400_000, 800_000, 1_500_000, 2_500_000] {
		for parts in [f32(1.0), 1.5] {
			contract := models.Contract{ base_salary: gross }
			engine := compute_payslip_configurable(contract, select_effective_components(components, '2026-06-01'), select_effective_brackets(brackets, '2026-06-01'), [], parts)
			legacy := calculate_pay_full_ci(contract, legacy_rules, [], parts)
			assert engine.net_pay == legacy.net_pay, 'net gross=${gross} parts=${parts} : engine=${engine.net_pay} legacy=${legacy.net_pay}'
			assert engine.total_taxes == legacy.total_taxes, 'taxes gross=${gross} parts=${parts} : engine=${engine.total_taxes} legacy=${legacy.total_taxes}'
			assert engine.gross_pay == legacy.gross_pay
			assert engine.tax_details.len == legacy.tax_details.len
		}
	}
}

fn test_employer_contributions_configurable() {
	components := [
		models.TaxComponent{ code: 'CNPS_RET_E', name: 'Retraite patronale', rate: 0.077, basis_type: 'plafonne', cap: 3_375_000, share: 'patronal', is_active: true },
		models.TaxComponent{ code: 'CNPS_PF', name: 'Prestations Familiales', rate: 0.0575, basis_type: 'plafonne', cap: 70_000, share: 'patronal', is_active: true },
		models.TaxComponent{ code: 'CNPS_AT', name: 'Accident du Travail', rate: 0.02, basis_type: 'plafonne', cap: 70_000, share: 'patronal', is_active: true },
		models.TaxComponent{ code: 'CNPS_RC', name: 'Régime Complémentaire', rate: 0.012, basis_type: 'plafonne', cap: 3_375_000, share: 'patronal', is_active: true },
		models.TaxComponent{ code: 'CMU', name: 'CMU salariale', rate: 0.0, basis_type: 'forfait', fixed_amount: 1000, share: 'salarial', is_active: true },
	]
	details, total := employer_contributions_configurable(components, 400_000)
	assert total == 30_800 + 4_025 + 1_400 + 4_800 // 41 025
	assert details.len == 4 // la part salariale est ignorée
}

fn test_select_effective_components_historical() {
	old := models.TaxComponent{ code: 'CNPS_RET', name: 'Retraite (2026)', rate: 0.063, basis_type: 'plafonne', cap: 3_375_000, share: 'salarial', effective_from: '2026-01-01', is_active: true }
	older := models.TaxComponent{ code: 'CNPS_RET', name: 'Retraite (2025)', rate: 0.045, basis_type: 'plafonne', cap: 3_000_000, share: 'salarial', effective_from: '2025-01-01', is_active: true }
	future := models.TaxComponent{ code: 'CNPS_RET', name: 'Retraite (futur)', rate: 0.080, basis_type: 'plafonne', cap: 4_000_000, share: 'salarial', effective_from: '2027-01-01', is_active: true }
	all := [older, old, future]
	selected := select_effective_components(all, '2026-06-01')
	assert selected.len == 1
	assert selected[0].rate == 0.063 // version 2026 (postérieure à 2025), le futur est exclu
	selected_future := select_effective_components(all, '2027-02-01')
	assert selected_future.len == 1
	assert selected_future[0].rate == 0.08
}

fn test_select_effective_brackets_versioned() {
	v2026 := models.TaxBracket{ component_code: 'IGR', lower_bound: 842_666, upper_bound: -1, rate: 0.375, flat: 98_633, effective_from: '2026-01-01', is_active: true }
	v2027 := models.TaxBracket{ component_code: 'IGR', lower_bound: 842_666, upper_bound: -1, rate: 0.40, flat: 104_000, effective_from: '2027-01-01', is_active: true }
	low := models.TaxBracket{ component_code: 'IGR', lower_bound: 0, upper_bound: 25_000, rate: 0.0, flat: 0, effective_from: '2027-01-01', is_active: true }
	baseline := models.TaxBracket{ component_code: 'IGR', lower_bound: 0, upper_bound: 25_000, rate: 0.0, flat: 0, effective_from: '', is_active: true }
	all := [low, v2026, v2027, baseline]

	sel_2026 := select_effective_brackets(all, '2026-06-01')
	assert sel_2026.len == 2 // v2026 + baseline ('' toujours applicables)
	match_2026 := bracket_amount_f(1_000_000, sel_2026)
	assert match_2026 == 1_000_000*0.375 - 98_633

	sel_2027 := select_effective_brackets(all, '2027-03-01')
	assert sel_2027.len == 3 // version 2027 complète [low, v2027] + baseline, la version 2026 est expulsée
	match_2027 := bracket_amount_f(1_000_000, sel_2027)
	assert match_2027 == 1_000_000*0.40 - 104_000
}