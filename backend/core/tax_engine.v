module core

import models
import math

// ==================== MOTEUR DE RÈGLES FISCALES DYNAMIQUES (Pilier 2.2) ====================
// Évalue une fiche de paie à la date de période : les composantes et tranches actives à cette
// date sont utilisées (effective_from <= période), ce qui rend les périodes passées stables
// lors d'un changement de loi.

pub const basis_brut = 'brut'
pub const basis_plafonne = 'plafonne'
pub const basis_forfait = 'forfait'
pub const basis_brut80 = 'brut80'
pub const share_salarial = 'salarial'
pub const share_patronal = 'patronal'

// component_amount calcule le montant d'une composante selon son mode d'assiette :
//   'brut'     : rate × brut
//   'plafonne' : rate × brut plafonné à cap
//   'forfait'  : montant forfaitaire fixe
//   'brut80'   : rate × 80% du brut (abattement forfaitaire légal)
pub fn component_amount(base_amount i64, comp models.TaxComponent) i64 {
	if comp.fixed_amount > 0 {
		return comp.fixed_amount
	}
	mut taxable_base := base_amount
	if comp.basis_type == basis_brut80 {
		taxable_base = i64(math.round(f64(base_amount) * 0.80))
	} else if comp.basis_type == basis_plafonne && comp.cap > 0 && base_amount > comp.cap {
		taxable_base = comp.cap
	}
	if taxable_base <= 0 || comp.rate <= 0.0 {
		return 0
	}
	return i64(math.round(f64(taxable_base) * comp.rate))
}

fn sorted_brackets(brackets []models.TaxBracket) []models.TaxBracket {
	mut sorted := brackets.clone()
	sorted.sort(a.lower_bound < b.lower_bound)
	return sorted
}

// bracket_amount_f calcule, en virgule flottante, le montant d'une base dans le barème
// de tranches (montant = base*rate - flat de la tranche contenant la base).
pub fn bracket_amount_f(base f64, brackets []models.TaxBracket) f64 {
	if base <= 0 {
		return 0.0
	}
	for b in sorted_brackets(brackets) {
		if !b.is_active {
			continue
		}
		if base < f64(b.lower_bound) {
			continue
		}
		if b.upper_bound >= 0 && base >= f64(b.upper_bound) {
			continue
		}
		amount := base*b.rate - f64(b.flat)
		if amount < 0 {
			return 0.0
		}
		return amount
	}
	return 0.0
}

// bracket_amount retourne le montant arrondi du barème progressif pour une base entière.
pub fn bracket_amount(base i64, brackets []models.TaxBracket) i64 {
	return i64(math.round(bracket_amount_f(f64(base), brackets)))
}

// select_effective_components garde, par code de composante, la version la plus récente
// dont la date d'effet (effective_from) est <= à la date de période. 'period' au format YYYY-MM-DD.
pub fn select_effective_components(components []models.TaxComponent, period string) []models.TaxComponent {
	mut best := map[string]models.TaxComponent{}
	for c in components {
		if !c.is_active {
			continue
		}
		if c.effective_from.len > 0 && c.effective_from > period {
			continue
		}
		if c.code in best {
			existing := best[c.code]
			if c.effective_from.len > 0 && c.effective_from > existing.effective_from {
				best[c.code] = c
			}
		} else {
			best[c.code] = c
		}
	}
	mut out := []models.TaxComponent{}
	for _, c in best {
		out << c
	}
	return out
}

// select_effective_brackets garde, par composante, uniquement les tranches de la VERSION
// (effective_from) la plus récente active à la date de période. Les tranches au effective_from
// vide ('') sont traitées comme un socle toujours applicables, combinées à la version retenue.
pub fn select_effective_brackets(brackets []models.TaxBracket, period string) []models.TaxBracket {
	mut best := map[string]string{}
	for b in brackets {
		if !b.is_active {
			continue
		}
		if b.effective_from.len > 0 && b.effective_from > period {
			continue
		}
		if b.component_code in best {
			if b.effective_from > best[b.component_code] {
				best[b.component_code] = b.effective_from
			}
		} else {
			best[b.component_code] = b.effective_from
		}
	}
	mut out := []models.TaxBracket{}
	for b in brackets {
		if !b.is_active {
			continue
		}
		if b.effective_from.len > 0 && b.effective_from > period {
			continue
		}
		want := best[b.component_code]
		if b.effective_from.len > 0 && b.effective_from != want {
			continue
		}
		out << b
	}
	return out
}

// compute_payslip_configurable calcule la paie complète à partir des composantes et tranches
// fournies (préalablement filtrées par date d'effet) — équivalent data-driven de
// calculate_pay_full_ci : cotisations sociales, IS, CN (tranches), IGR (tranches + quotient familial).
pub fn compute_payslip_configurable(contract models.Contract, components []models.TaxComponent, brackets []models.TaxBracket, adjustments []models.Adjustment, tax_parts f32) CalculationResult {
	mut total_gross := contract.base_salary
	for adj in adjustments {
		total_gross += adj.amount
	}

	cn_brackets := brackets.filter(it.component_code == 'CN')
	igr_brackets := brackets.filter(it.component_code == 'IGR')

	mut is_amount := i64(0)
	mut cn_amount := i64(0)
	mut total_taxes := i64(0)
	mut tax_details := []TaxLine{}

	for c in components {
		if c.share != share_salarial {
			continue
		}
		match c.code {
			'IS' {
				amt := component_amount(total_gross, c)
				if amt > 0 {
					is_amount = amt
					total_taxes += amt
					tax_details << TaxLine{ name: c.name, amount: amt }
				}
			}
			'CN' {
				if cn_brackets.len == 0 {
					continue
				}
				base := i64(math.round(f64(total_gross) * 0.80))
				amt := bracket_amount(base, cn_brackets)
				if amt > 0 {
					cn_amount = amt
					total_taxes += amt
					tax_details << TaxLine{ name: c.name, amount: amt }
				}
			}
			'IGR' {
				// calculé après (nécessite IS et CN)
			}
			else {
				amt := component_amount(total_gross, c)
				if amt > 0 {
					total_taxes += amt
					tax_details << TaxLine{ name: c.name, amount: amt }
				}
			}
		}
	}

	for c in components {
		if c.code != 'IGR' || c.share != share_salarial {
			continue
		}
		mut amt := i64(0)
		if igr_brackets.len > 0 {
			parts := if tax_parts < 1.0 { f64(1.0) } else { f64(tax_parts) }
			r_base := (f64(total_gross) * 0.80) - f64(is_amount) - f64(cn_amount)
			if r_base > 0 {
				q := (r_base * 0.85) / parts
				single := bracket_amount_f(q, igr_brackets)
				amt = i64(math.round(single * parts))
			}
		} else {
			amt = component_amount(total_gross, c)
		}
		if amt > 0 {
			total_taxes += amt
			tax_details << TaxLine{ name: c.name, amount: amt }
		}
	}

	return CalculationResult{
		gross_pay: total_gross
		total_taxes: total_taxes
		net_pay: total_gross - total_taxes
		tax_details: tax_details
	}
}

// employer_contributions_configurable calcule les cotisations patronales à partir des composantes
// marquées 'patronal'. Retourne la liste détaillée + le total (équivalent de calculate_employer_contributions_ci).
pub fn employer_contributions_configurable(components []models.TaxComponent, gross i64) ([]TaxLine, i64) {
	mut details := []TaxLine{}
	mut total := i64(0)
	for c in components {
		if c.share != share_patronal {
			continue
		}
		amount := component_amount(gross, c)
		if amount > 0 {
			details << TaxLine{ name: c.name, amount: amount }
			total += amount
		}
	}
	return details, total
}