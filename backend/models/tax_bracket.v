module models

// Tranche d'un barème progressif (CN, IGR) paramétrable (Pilier 2.2).
// Montant dans la tranche = round(base * rate - flat), avec -1 en upper_bound pour la borne infinie.
// La vérification de non-recouvrement des tranches est faite à la création/mise à jour.
pub struct TaxBracket {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	component_code  string // code du composant associé (ex: 'CN', 'IGR')
	lower_bound     i64 // borne inférieure INCLUSE
	upper_bound     i64 // borne supérieure EXCLUE (-1 = non bornée)
	rate            f64 // taux marginal de la tranche (décimal)
	flat            i64 // constante : amount = round(base*rate - flat)
	effective_from  string // 'YYYY-MM-DD' ('' = toujours applicable)
	is_active       bool @[default: true]
}