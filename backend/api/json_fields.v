module api

import json2

// json_keys retourne les clés de premier niveau d'un objet JSON.
//
// json2.decode ignore les attributs @[default] des structs : un champ absent du
// corps reçoit la valeur zéro (false, 0). Pour appliquer un défaut métier — ou
// conserver la valeur existante lors d'une mise à jour — il faut savoir si le
// client a réellement envoyé le champ.
fn json_keys(body string) map[string]bool {
	mut keys := map[string]bool{}
	root := json2.decode[json2.Any](body) or { return keys }
	if root is map[string]json2.Any {
		for k, _ in root {
			keys[k] = true
		}
	}
	return keys
}

// is_active_default retourne la valeur décodée si `is_active` est présent dans le
// corps, sinon true (défaut à la création).
fn is_active_default(body string, decoded_is_active bool) bool {
	return if 'is_active' in json_keys(body) { decoded_is_active } else { true }
}
