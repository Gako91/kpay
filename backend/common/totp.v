module common

import encoding.base32
import encoding.hex
import crypto.hmac
import crypto.sha1
import crypto.sha256
import crypto.rand
import time

// ==================== SECRET & CODES DE SECOURS ====================

// generate_mfa_secret génère un secret TOTP : 20 octets aléatoires encodés en base32 (RFC 4648).
pub fn generate_mfa_secret() !string {
	bytes := rand.bytes(20)!
	return base32.encode(bytes).bytestr().replace('=', '')
}

// generate_backup_codes génère `count` codes de secours (1 usage, à stocker uniquement hashés).
pub fn generate_backup_codes(count int) ![]string {
	alphabet := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
	mut codes := []string{}
	for i := 0; i < count; i++ {
		mut code := ''
		for _ in 0 .. 10 {
			b := rand.bytes(1)!
			code += alphabet[int(b[0]) % alphabet.len..int(b[0]) % alphabet.len + 1]
		}
		codes << code
	}
	return codes
}

// hash_backup_code hache un code de secours (SHA-256 hex) avant stockage.
pub fn hash_backup_code(code string) string {
	return hex.encode(sha256.sum(code.bytes()))
}

// ==================== BASE32 ====================

// base32_pad complète un secret sans padding pour sa longueur multiple de 8.
fn base32_pad(s string) string {
	mut r := s
	for r.len % 8 != 0 {
		r += '='
	}
	return r
}

// ==================== TOTP (RFC 6238, SHA-1, 6 chiffres, 30s) ====================

// totp_code calcule le code TOTP pour un `secret` base32 à un instant donné (secondes Unix).
pub fn totp_code(secret string, at_unix i64) !string {
	key := base32.decode(base32_pad(secret).bytes()) or {
		return error('Secret MFA invalide')
	}
	mut counter := u64(at_unix / 30)

	// Contre 8 octets (network byte order)
	mut msg := []u8{len: 8}
	for i := 0; i < 8; i++ {
		msg[7 - i] = u8(counter) & 0xff
		counter >>= 8
	}

	hm := hmac.new(key, msg, sha1.sum, sha1.block_size)
	offset := int(hm[hm.len - 1] & 0x0f)
	code := (u32(hm[offset]) << 24 | u32(hm[offset + 1]) << 16 | u32(hm[offset + 2]) << 8 | u32(hm[offset + 3])) & 0x7fffffff
	return '${int(code % 1000000):06d}'
}

// verify_totp vérifie un code TOTP avec une fenêtre de +/- `window` pas de 30s.
pub fn verify_totp(secret string, code string, window int) bool {
	if secret.len == 0 || code.len == 0 {
		return false
	}
	now := time.now().unix()
	for w := -window; w <= window; w++ {
		candidate := totp_code(secret, now + i64(w) * 30) or { return false }
		if candidate == code {
			return true
		}
	}
	return false
}

// ==================== OTPAUTH URI ====================

// otpauth_uri construit l'URI d'enrôlement compatible Google Authenticator / FreeOTP.
pub fn otpauth_uri(secret string, account string, issuer string) string {
	label := '${issuer}:${account}'
	params := 'secret=${secret}&issuer=${issuer}&digits=6&period=30'
	return 'otpauth://totp/${label}?${params}'
}