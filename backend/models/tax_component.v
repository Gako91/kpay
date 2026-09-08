module models

// Composante de cotisation paramétrable (Pilier 2.2 — moteur de règles fiscales dynamiques).
// Versionnée par `effective_from` (date d'effet au format YYYY-MM-DD) : une période de paie
// utilise la version active la plus récente dont la date d'effet <= début de période.
pub struct TaxComponent {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	code            string // code interne canonique (ex: 'CNPS_RET', 'CMU', 'IS', 'CN', 'IGR')
	name            string // libellé affiché (ex: "CNPS Retraite")
	rate            f64 // taux en décimal (ex: 0.063 = 6.3%)
	basis_type      string // 'brut' | 'plafonne' | 'forfait' | 'brut80'
	cap             i64 // plafond d'assiette en FCFA (0 = non plafonné)
	fixed_amount    i64 // montant forfaitaire en FCFA (0 = taux appliqué)
	share           string // 'salarial' | 'patronal'
	effective_from  string // 'YYYY-MM-DD' ('' = toujours applicable)
	is_active       bool @[default: true]
	country         string // code pays (ex: 'CI')
}