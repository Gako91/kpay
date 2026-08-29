module core

import models


// Structure pour stocker les totaux d'une ligne de taxe
pub struct TaxLine {
	pub:
	name   string
	amount i64
}

pub struct CalculationResult {
	pub:
	gross_pay    i64
	net_pay      i64
	total_taxes  i64
	tax_details  []TaxLine
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

	// 2. Appliquer les taxes (DOD style : itération sur les règles)
	for rule in rules {
		if !rule.is_employer { // On ne calcule ici que la part salariale pour le net
			tax_amount := i64(f64(total_gross) * rule.rate)
			total_taxes += tax_amount
			tax_details << TaxLine{ name: rule.name, amount: tax_amount }
		}
	}

	return CalculationResult{
		gross_pay:   total_gross
		total_taxes: total_taxes
		net_pay:     total_gross - total_taxes
		tax_details: tax_details
	}
}

// Calcule la rémunération des heures supplémentaires (majoration 25%)
pub fn calculate_overtime(hourly_rate i64, overtime_hours f32) i64 {
	overtime_multiplier := 1.25
	return i64(f64(hourly_rate) * f64(overtime_hours) * overtime_multiplier)
}

// Calcule le salaire net après application de règles fiscales
pub fn apply_tax_rules(gross_pay i64, rules []models.TaxRule, employer_part bool) i64 {
	mut total_tax := i64(0)
	for rule in rules {
		if rule.is_employer == employer_part {
			total_tax += i64(f64(gross_pay) * rule.rate)
		}
	}
	return total_tax
}
