module dto

import models
import core

// ==================== COMPOSANTES DE COTISATION (Pilier 2.2) ====================

// validate_effective_from vérifie une date d'effet au format YYYY-MM-DD ('' = non renseignée).
fn validate_effective_from(value string) ! {
	if value.len == 0 {
		return
	}
	if value.len != 10 || value[4] != `-` || value[7] != `-` {
		return error("Validation échouée : 'effective_from' doit être au format YYYY-MM-DD")
	}
}

// validate_tax_component valide une composante de cotisation avant création/mise à jour.
pub fn validate_tax_component(c models.TaxComponent) ! {
	if c.code.trim_space().len < 2 {
		return error("Validation échouée : 'code' doit contenir au moins 2 caractères (reçu: '${c.code}')")
	}
	if c.name.trim_space().len < 2 {
		return error("Validation échouée : 'name' doit contenir au moins 2 caractères")
	}
	if c.rate < 0 || c.rate > 1 {
		return error("Validation échouée : 'rate' doit être compris entre 0 et 1 (ex: 0.063)")
	}
	if c.basis_type.len == 0 {
		return error("Validation échouée : 'basis_type' est requis (brut|plafonne|forfait|brut80)")
	}
	if c.share != 'salarial' && c.share != 'patronal' {
		return error("Validation échouée : 'share' doit être 'salarial' ou 'patronal'")
	}
	if c.cap < 0 || c.fixed_amount < 0 {
		return error("Validation échouée : 'cap' et 'fixed_amount' ne peuvent pas être négatifs")
	}
	validate_effective_from(c.effective_from)!
}

// ==================== TRANCHES (Pilier 2.2) ====================

// validate_tax_bracket valide une tranche avant création/mise à jour.
pub fn validate_tax_bracket(b models.TaxBracket) ! {
	if b.component_code != 'CN' && b.component_code != 'IGR' {
		return error("Validation échouée : 'component_code' doit être 'CN' ou 'IGR'")
	}
	if b.lower_bound < 0 {
		return error("Validation échouée : 'lower_bound' ne peut pas être négatif")
	}
	if b.upper_bound != -1 && b.upper_bound <= b.lower_bound {
		return error("Validation échouée : 'upper_bound' doit être strictement supérieur à 'lower_bound' (ou -1 pour non bornée)")
	}
	if b.rate < 0 || b.rate > 1 {
		return error("Validation échouée : 'rate' doit être compris entre 0 et 1")
	}
	if b.flat < 0 {
		return error("Validation échouée : 'flat' ne peut pas être négatif")
	}
	validate_effective_from(b.effective_from)!
}

// validate_brackets_no_overlap vérifie que les tranches actives d'un même barème ne se recouvrent pas.
pub fn validate_brackets_no_overlap(brackets []models.TaxBracket) ! {
	mut by_code := map[string][]models.TaxBracket{}
	for b in brackets {
		if b.is_active {
			by_code[b.component_code] << b
		}
	}
	for code, list in by_code {
		mut sorted := list.clone()
		sorted.sort(a.lower_bound < b.lower_bound)
		for i in 0 .. sorted.len {
			cur := sorted[i]
			for j in i + 1 .. sorted.len {
				other := sorted[j]
				if cur.upper_bound < 0 || other.lower_bound < cur.upper_bound {
					return error("Validation échouée : tranches recouvrantes pour '${code}' ([${cur.lower_bound}, ${cur.upper_bound}) et [${other.lower_bound}, ${other.upper_bound}))")
				}
			}
		}
	}
}

// ==================== SIMULATION D'IMPACT (Pilier 2.2) ====================

// TaxImpactRequest : simulation d'un salaire brut donné contre la configuration actuelle
// et une configuration proposée (composantes + tranches), à une date de période donnée.
pub struct TaxImpactRequest {
pub mut:
	gross      i64
	tax_parts  f32
	period     string // date de la fiche simulée (YYYY-MM-DD)
	components []models.TaxComponent
	brackets   []models.TaxBracket
}

pub struct TaxImpactResult {
pub mut:
	net     i64
	taxes   i64
	details []core.TaxLine
}

pub struct TaxImpactResponse {
pub mut:
	current     TaxImpactResult
	proposed    TaxImpactResult
	delta_net   i64
}

pub fn (r TaxImpactRequest) validate() ! {
	if r.gross <= 0 {
		return error("Validation échouée : 'gross' doit être supérieur à 0")
	}
	if r.tax_parts < 1.0 {
		return error("Validation échouée : 'tax_parts' doit être au minimum 1.0")
	}
	validate_effective_from(r.period)!
}