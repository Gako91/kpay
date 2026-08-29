module common

import rand
import crypto.md5

// Formate un montant en centimes vers une chaîne lisible
// Ex: 450000 -> "4 500,00 FCFA"
pub fn format_money(cents i64, currency string) string {
	euros := cents / 100
	remaining_cents := cents % 100

	// Formatage avec séparateur de milliers
	euros_str := format_with_thousands(euros)

	symbol := match currency {
		'EUR' { '€' }
		'USD' { '$' }
		'XOF' { 'FCFA' }
		else { currency }
	}

	return '${euros_str},${remaining_cents:02d} ${symbol}'
}

// Ajoute les séparateurs de milliers
fn format_with_thousands(n i64) string {
	s := '${n}'
	if s.len <= 3 {
		return s
	}

	mut result := ''
	mut count := 0
	for i := s.len - 1; i >= 0; i-- {
		if count > 0 && count % 3 == 0 {
			result = ' ' + result
		}
		result = s[i..i + 1] + result
		count++
	}
	return result
}

// Valide un format d'email basique
pub fn is_valid_email(email string) bool {
	if email.len < 5 {
		return false
	}
	at_pos := email.index('@') or { return false }
	dot_pos := email.last_index('.') or { return false }

	return at_pos > 0 && dot_pos > at_pos + 1 && dot_pos < email.len - 1
}

// Génère un UUID v4 simple
pub fn generate_uuid() string {
	bytes := rand.bytes(16) or { return '' }
	hex := bytes.hex()
	return '${hex[0..8]}-${hex[8..12]}-${hex[12..16]}-${hex[16..20]}-${hex[20..32]}'
}

// Génère un hash MD5 pour un mot de passe (à remplacer par bcrypt en prod)
pub fn hash_password(password string) string {
	return md5.hexhash(password)
}

// Arrondi légal français (0.5 -> valeur supérieure)
pub fn round_legal(value f64) i64 {
	return i64(value + 0.5)
}
