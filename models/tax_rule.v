module models

// Règle fiscale (cotisations)
pub struct TaxRule {
pub:
	id          int @[primary; sql: serial]
	name        string // ex: "Cotisation Retraite", "CSG"
	rate        f64    // ex: 0.065 pour 6.5%
	is_employer bool   // Part patronale ou salariale
	country     string // Pays par défaut: CI
}
