module common

fn test_rate_limiter_allows_until_limit() {
	mut rl := new_rate_limiter(3, 60)
	// 3 requêtes autorisées
	assert rl.allow('127.0.0.1')
	assert rl.allow('127.0.0.1')
	assert rl.allow('127.0.0.1')
	// 4e requête refusée
	assert !rl.allow('127.0.0.1')
	// Une autre IP n'est pas affectée
	assert rl.allow('10.0.0.1')
}

fn test_rate_limiter_isolation_per_key() {
	mut rl := new_rate_limiter(1, 60)
	assert rl.allow('client-a')
	assert !rl.allow('client-a')
	assert rl.allow('client-b')
}
