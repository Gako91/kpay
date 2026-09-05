module common

fn test_generate_and_verify_jwt() {
	secret := 'test_secret_123'
	token := generate_jwt('paie.admin', 'admin', secret, 3600, 'kpay') or {
		assert false, 'JWT generation failed: ${err}'
		return
	}
	assert token.split('.').len == 3

	claims := verify_jwt(token, secret) or {
		assert false, 'JWT verification failed: ${err}'
		return
	}
	assert claims.sub == 'paie.admin'
	assert claims.role == 'admin'
	assert claims.iss == 'kpay'
}

fn test_jwt_wrong_secret() {
	token := generate_jwt('user', 'employee', 'secret_1', 3600, 'kpay') or { return }
	_ := verify_jwt(token, 'wrong_secret') or {
		// Expected: verification must fail with wrong secret
		return
	}
	assert false, 'JWT should be rejected with wrong secret'
}

fn test_jwt_expired() {
	// exp in the past
	token := generate_jwt('user', 'employee', 'secret_x', -10, 'kpay') or { return }
	_ = verify_jwt(token, 'secret_x') or {
		return
	}
	assert false, 'JWT should be rejected when expired'
}

fn test_hash_verify_password() {
	hashed := hash_password('motdepasse123')
	assert hashed.len > 0
	assert verify_password('motdepasse123', hashed)
	assert !verify_password('mauvais', hashed)
}

fn test_round_legal() {
	assert round_legal(1.5) == 2
	assert round_legal(1.4) == 1
}
