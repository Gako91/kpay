module models

// Règle fiscale (cotisations et retenues)
pub struct TaxRule {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	name            string // ex: "CNPS Retraite", "CMU"
	rate            f64 // ex: 0.063 pour 6.3%
	is_employer     bool // Part patronale ou salariale
	ceiling         i64 // Plafond d'assiette en FCFA (0 = non plafonné, ex: 3375000 pour Retraite, 70000 pour PF/AT)
	fixed_amount    i64 // Montant forfaitaire en FCFA (ex: 1000 pour CMU, 0 si taux appliqué)
	country         string // Code pays (ex: 'CI')
}
