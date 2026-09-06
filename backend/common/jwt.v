module common

import encoding.base64
import x.json2
import crypto.hmac
import crypto.sha256
import time

// Claims représente le contenu (payload) d'un token JWT.
struct Claims {
pub mut:
	sub  string
	role string
	org  int
	exp  i64
	iat  i64
	iss  string
}

// base64url_encode encode des bytes en base64url sans padding (=).
fn base64url_encode(data []u8) string {
	mut s := base64.url_encode(data).replace('=', '')
	return s
}

// base64url_decode décode une chaîne base64url.
fn base64url_decode(s string) ![]u8 {
	mut pad := s
	for pad.len % 4 != 0 {
		pad += '='
	}
	return base64.url_decode(pad)
}

// generate_jwt crée un token JWT signé en HS256.
// `sub` identifiant (ex: user id ou username)
// `role` rôle de l'utilisateur
// `org` identifiant de l'organisation (tenant)
// `secret` clé secrète de signature
// `ttl_secs` durée de validité en secondes
pub fn generate_jwt(sub string, role string, org int, secret string, ttl_secs int, issuer string) !string {
	header_json := '{"alg":"HS256","typ":"JWT"}'
	header_b64 := base64url_encode(header_json.bytes())

	now := time.now().unix()
	claims := Claims{
		sub: sub
		role: role
		org: org
		exp: now + i64(ttl_secs)
		iat: now
		iss: issuer
	}
	claims_json := json2.encode(claims)
	claims_b64 := base64url_encode(claims_json.bytes())

	unsigned := '${header_b64}.${claims_b64}'
	sig := sign_hs256(unsigned, secret)
	return '${unsigned}.${sig}'
}

// verify_jwt vérifie un token JWT et retourne les claims décodés.
pub fn verify_jwt(token string, secret string) !JwtClaims {
	parts := token.split('.')
	if parts.len != 3 {
		return error('Token JWT invalide (structure)')
	}
	header_b64 := parts[0]
	claims_b64 := parts[1]
	signature := parts[2]

	unsigned := '${header_b64}.${claims_b64}'
	expected_sig := sign_hs256(unsigned, secret)
	if expected_sig != signature {
		return error('Signature JWT invalide')
	}

	claims_data := base64url_decode(claims_b64)!
	claims := json2.decode[JwtClaims](claims_data.bytestr()) or {
		return error('Claims JWT invalides: ${err}')
	}

	if claims.exp > 0 && claims.exp < time.now().unix() {
		return error('Token JWT expiré')
	}

	return claims
}

// sign_hs256 signe une chaîne avec HMAC-SHA256 puis base64url.
fn sign_hs256(data string, secret string) string {
	digest := hmac.new(secret.bytes(), data.bytes(), sha256.sum, sha256.block_size)
	return base64url_encode(digest)
}

// JwtClaims représente les claims décodés d'un token JWT.
pub struct JwtClaims {
pub:
	sub  string
	role string
	org  int
	exp  i64
	iat  i64
	iss  string
}
