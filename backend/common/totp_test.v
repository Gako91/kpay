module common

import time

fn test_totp_rfc6238_vector() {
	// Vecteur RFC 6238 (SHA-1, seed 12345678901234567890) — code 6 chiffres
	secret := 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
	// T = 59 (unix 59) → counter 1 → code attendu 228821 (RFC 6238, 8 digits : 94287082 → 6 digits 287082)
	code := totp_code(secret, 59)!
	assert code == '287082'

	// T = 1111111109 → 8 digits 07081804 → 6 digits 081804
	code2 := totp_code(secret, 1111111109)!
	assert code2 == '081804'

	// T = 2000000000 → 8 digits 69279037 → 6 digits 279037
	code3 := totp_code(secret, 2000000000)!
	assert code3 == '279037'
}

fn test_totp_verify_window() {
	secret := 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
	now := time.now().unix()
	now_code := totp_code(secret, now)!

	assert verify_totp(secret, now_code, 1)

	// Un code d'un pas précédent (30s en arrière) doit passer avec fenêtre >= 1
	prev_code := totp_code(secret, now - 30)!
	assert verify_totp(secret, prev_code, 1)
	assert !verify_totp(secret, '000000', 0)
}

fn test_mfa_secret_and_backup_codes() {
	secret := generate_mfa_secret() or { panic(err) }
	// base32 sans padding, longueur 32 (20 octets = 32 chars sans '=')
	assert secret.len == 32
	assert secret.to_upper() == secret

	codes := generate_backup_codes(10) or { panic(err) }
	assert codes.len == 10
	for c in codes {
		assert c.len == 10
		// Hachage reproductible pour la vérification
		assert hash_backup_code(c) == hash_backup_code(c.to_upper())
		assert hash_backup_code(c) != hash_backup_code('XXXX')
	}

	uri := otpauth_uri(secret, 'user', 'KPay')
	assert uri.starts_with('otpauth://totp/KPay:user?secret=')
	assert uri.contains('issuer=KPay')
	assert uri.contains('period=30')
}