module common

import rand
import crypto.bcrypt

// Formate un montant entier (en unités de la devise, ex: FCFA) vers une chaîne lisible.
// Ex: 450000 -> "450 000 FCFA"
pub fn format_money(amount i64, currency string) string {
	// Les montants sont stockés en unités entières (pas en centimes)
	full_str := format_with_thousands(amount)

	symbol := match currency {
		'EUR' { '€' }
		'USD' { '$' }
		'XOF' { 'FCFA' }
		else { currency }
	}

	return '${full_str} ${symbol}'
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

// Hash un mot de passe avec bcrypt (coût par défaut 10).
pub fn hash_password(password string) string {
	return bcrypt.generate_from_password(password.bytes(), 10) or { '' }
}

// verify_password vérifie qu'un mot de passe correspond à un hash bcrypt.
pub fn verify_password(password string, hashed string) bool {
	bcrypt.compare_hash_and_password(password.bytes(), hashed.bytes()) or {
		return false
	}
	return true
}

// Arrondi légal français (0.5 -> valeur supérieure)
pub fn round_legal(value f64) i64 {
	return i64(value + 0.5)
}
