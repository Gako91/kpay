module models

import crypto.sha256

// Types de déclaration enregistrés au registre (Pilier 5.1)
pub const declaration_disa = 'disa' // DISA annuelle CNPS (fichier d'entrée E-DISA)

// DeclarationExport est une entrée du registre des déclarations sociales et fiscales.
// Chaque export est scellé : le fichier est conservé tel quel (MinIO), son empreinte
// SHA-256 est enregistrée, et les entrées d'une organisation forment une chaîne
// (chain_hash = SHA-256 de l'entrée précédente + des métadonnées de celle-ci) :
// modifier ou supprimer une entrée ancienne casse la chaîne et se détecte.
@[table: 'declaration_export']
pub struct DeclarationExport {
pub:
	id              int @[primary; sql: serial]
	organization_id int
	kind            string // 'disa'
	period          string // ex: '2026' (année déclarée)
	version         int    // 1, 2… : un nouvel export de la même période crée une version
	file_name       string // nom proposé au téléchargement
	object_name     string // objet MinIO (préfixé par l'organisation)
	content_type    string
	sha256          string // empreinte du fichier
	prev_hash       string // chain_hash de l'entrée précédente de l'organisation ('' = première)
	chain_hash      string
	row_count       int
	total_amount    i64 // ex: masse salariale brute déclarée
	created_by      string
	sealed_at       string // horodatage RFC 3339 UTC, inclus dans le chaînage
}

// declaration_chain_hash calcule l'empreinte chaînée d'une entrée du registre.
pub fn declaration_chain_hash(prev_hash string, d DeclarationExport) string {
	payload := [prev_hash, d.organization_id.str(), d.kind, d.period, d.version.str(), d.sha256,
		d.row_count.str(), d.total_amount.str(), d.created_by, d.sealed_at].join('|')
	return sha256.hexhash(payload)
}
