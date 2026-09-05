module core

import models
import math

// Structure pour stocker les totaux d'une ligne de taxe
pub struct TaxLine {
pub:
	name   string
	amount i64
}

pub struct CalculationResult {
pub:
	gross_pay   i64
	net_pay     i64
	total_taxes i64
	tax_details []TaxLine
}

// calculate_tax_amount calcule le montant d'une règle fiscale en tenant compte des plafonds et forfaits
pub fn calculate_tax_amount(base_amount i64, rule models.TaxRule) i64 {
	// 1. Si montant fixe forfaitaire défini (ex: CMU = 1 000 FCFA)
	if rule.fixed_amount > 0 {
		return rule.fixed_amount
	}

	// 2. Déterminer l'assiette soumise à cotisation (application du plafond si défini)
	mut taxable_base := base_amount
	if rule.ceiling > 0 && taxable_base > rule.ceiling {
		taxable_base = rule.ceiling
	}

	if taxable_base <= 0 || rule.rate <= 0.0 {
		return 0
	}

	return i64(math.round(f64(taxable_base) * rule.rate))
}

// calculate_pay Moteur de calcul pur
pub fn calculate_pay(contract models.Contract, rules []models.TaxRule, adjustments []models.Adjustment) CalculationResult {
	mut total_gross := contract.base_salary
	mut total_taxes := i64(0)
	mut tax_details := []TaxLine{}

	// 1. Ajouter les ajustements (primes/bonus)
	for adj in adjustments {
		total_gross += adj.amount
	}

	// 2. Appliquer les taxes salariales (avec plafonds et forfaits)
	for rule in rules {
		if !rule.is_employer {
			tax_amount := calculate_tax_amount(total_gross, rule)
			total_taxes += tax_amount
			tax_details << TaxLine{ name: rule.name, amount: tax_amount }
		}
	}

	return CalculationResult{
		gross_pay: total_gross
		total_taxes: total_taxes
		net_pay: total_gross - total_taxes
		tax_details: tax_details
	}
}

// Calcule la rémunération des heures supplémentaires selon le barème légal CI :
// - De 1 à 6 heures (41e à 46e heure) : majoration 15% (taux 1.15)
// - De 7 à 8 heures (47e à 48e heure) : majoration 50% (taux 1.50)
// - Au-delà de 8 heures : majoration 50%
pub fn calculate_overtime_ci(hourly_rate i64, overtime_hours f32) i64 {
	if overtime_hours <= 0 {
		return 0
	}
	mut total_pay := f64(0)
	hours := f64(overtime_hours)
	base_h := f64(hourly_rate)

	if hours <= 6.0 {
		total_pay = hours * base_h * 1.15
	} else if hours <= 8.0 {
		total_pay = (6.0 * base_h * 1.15) + (hours - 6.0) * base_h * 1.50
	} else {
		total_pay = (6.0 * base_h * 1.15) + (2.0 * base_h * 1.50) + (hours - 8.0) * base_h * 1.50
	}

	return i64(math.round(total_pay))
}

// ==================== FISCALITE IVOIRIENNE (DGI COTE D'IVOIRE) ====================

// calculate_is_ci calcule l'Impôt sur Salaire (IS) en Côte d'Ivoire (1.2% du brut imposable abattu de 20%)
// IS = 80% * Salaire Brut * 1.2% = 0.8 * Brut * 0.012 = Brut * 0.0096
pub fn calculate_is_ci(taxable_gross i64) i64 {
	if taxable_gross <= 0 {
		return 0
	}
	// Assiette fiscale avec abattement forfaitaire de 20%
	base := f64(taxable_gross) * 0.80
	return i64(math.round(base * 0.012))
}

// calculate_cn_ci calcule la Contribution Nationale (CN) selon le barème progressif mensuel ivoirien
// Barème sur l'assiette après abattement de 20% :
// - De 0 à 50 000 FCFA : 0%
// - De 50 001 à 130 000 FCFA : 1.5%
// - De 130 001 à 200 000 FCFA : 5%
// - Au-delà de 200 000 FCFA : 10%
pub fn calculate_cn_ci(taxable_gross i64) i64 {
	if taxable_gross <= 0 {
		return 0
	}
	base := f64(taxable_gross) * 0.80
	if base <= 50_000.0 {
		return 0
	}
	mut cn := f64(0)
	if base <= 130_000.0 {
		cn = (base - 50_000.0) * 0.015
	} else if base <= 200_000.0 {
		cn = (130_000.0 - 50_000.0) * 0.015 + (base - 130_000.0) * 0.05
	} else {
		cn = (130_000.0 - 50_000.0) * 0.015 + (200_000.0 - 130_000.0) * 0.05 + (base - 200_000.0) * 0.10
	}
	return i64(math.round(cn))
}

// calculate_igr_ci calcule l'Impôt Général sur le Revenu (IGR) mensuel en Côte d'Ivoire
// Formule légale DGI CI :
// 1. Revenu brut imposable R = 80% * Brut - Retenue IS - Retenue CN
// 2. Abattement forfaitaire pour frais professionnels de 15% : R' = 85% * R
// 3. Quotient familial Q = R' / N (où N est le nombre de parts fiscales, minimum 1.0)
// 4. Barème progressif mensuel IGR par tranche sur Q
pub fn calculate_igr_ci(taxable_gross i64, is_amount i64, cn_amount i64, tax_parts f32) i64 {
	if taxable_gross <= 0 {
		return 0
	}
	parts := if tax_parts < 1.0 { f64(1.0) } else { f64(tax_parts) }

	// R = 80% * Brut - IS - CN
	r_base := (f64(taxable_gross) * 0.80) - f64(is_amount) - f64(cn_amount)
	if r_base <= 0 {
		return 0
	}

	// Abattement de 15% pour frais professionnels
	r_net := r_base * 0.85
	q := r_net / parts

	mut igr_single := f64(0)
	if q <= 25_000.0 {
		igr_single = 0.0
	} else if q <= 45_583.0 {
		igr_single = (q * 10.0 / 110.0) - 2_273.0
	} else if q <= 81_583.0 {
		igr_single = (q * 15.0 / 115.0) - 4_076.0
	} else if q <= 126_583.0 {
		igr_single = (q * 20.0 / 120.0) - 7_031.0
	} else if q <= 220_583.0 {
		igr_single = (q * 25.0 / 125.0) - 11_250.0
	} else if q <= 389_583.0 {
		igr_single = (q * 35.0 / 135.0) - 24_306.0
	} else if q <= 842_666.0 {
		igr_single = (q * 45.0 / 145.0) - 44_181.0
	} else {
		igr_single = (q * 60.0 / 160.0) - 98_633.0
	}

	if igr_single < 0 {
		igr_single = 0.0
	}

	total_igr := igr_single * parts
	return i64(math.round(total_igr))
}

// calculate_pay_full_ci calcule la paie complète intégrant cotisations CNPS, CMU et fiscalité DGI CI
pub fn calculate_pay_full_ci(contract models.Contract, rules []models.TaxRule, adjustments []models.Adjustment, tax_parts f32) CalculationResult {
	mut total_gross := contract.base_salary
	mut total_taxes := i64(0)
	mut tax_details := []TaxLine{}

	// 1. Ajouter les primes/ajustements
	for adj in adjustments {
		total_gross += adj.amount
	}

	// 2. Cotisations sociales (CNPS + CMU)
	for rule in rules {
		if !rule.is_employer {
			tax_amount := calculate_tax_amount(total_gross, rule)
			total_taxes += tax_amount
			tax_details << TaxLine{ name: rule.name, amount: tax_amount }
		}
	}

	// 3. Impôts et taxes sur salaires (DGI CI)
	is_amount := calculate_is_ci(total_gross)
	if is_amount > 0 {
		total_taxes += is_amount
		tax_details << TaxLine{ name: 'Impôt sur Salaire (IS)', amount: is_amount }
	}

	cn_amount := calculate_cn_ci(total_gross)
	if cn_amount > 0 {
		total_taxes += cn_amount
		tax_details << TaxLine{ name: 'Contribution Nationale (CN)', amount: cn_amount }
	}

	igr_amount := calculate_igr_ci(total_gross, is_amount, cn_amount, tax_parts)
	if igr_amount > 0 {
		total_taxes += igr_amount
		tax_details << TaxLine{ name: 'Impôt Général Revenu (IGR)', amount: igr_amount }
	}

	return CalculationResult{
		gross_pay: total_gross
		total_taxes: total_taxes
		net_pay: total_gross - total_taxes
		tax_details: tax_details
	}
}

// ==================== COTISATIONS PATRONALES ====================

// calculate_employer_contributions_ci calcule les cotisations patronales (part employeur)
// à partir des règles fiscales marquées is_employer == true, en appliquant les mêmes
// plafonds et forfaits que la partie salariale. Retourne liste détaillée + total.
pub fn calculate_employer_contributions_ci(rules []models.TaxRule, gross i64) ([]TaxLine, i64) {
	mut details := []TaxLine{}
	mut total := i64(0)
	for rule in rules {
		if rule.is_employer {
			amount := calculate_tax_amount(gross, rule)
			if amount > 0 {
				details << TaxLine{ name: rule.name, amount: amount }
				total += amount
			}
		}
	}
	return details, total
}
