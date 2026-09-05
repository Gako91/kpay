module common

import sync
import time

// Bucket est l'état de comptage pour une clé (IP) sur une fenêtre fixe.
struct Bucket {
mut:
	count     int
	window_at time.Time
}

// RateLimiter implémente un limiteur de débit simple (fenêtre fixe) par clé.
pub struct RateLimiter {
mut:
	buckets    map[string]Bucket
	mu         sync.RwMutex
	max_events int
	window_sec i64
}

// max_buckets est une borne haute pour éviter une croissance de mémoire illimitée
const max_buckets = 10000

// new_rate_limiter crée un limiteur autorisant max_events requêtes par fenêtre_sec.
pub fn new_rate_limiter(max_events int, window_sec int) &RateLimiter {
	return &RateLimiter{
		buckets: map[string]Bucket{}
		max_events: max_events
		window_sec: i64(window_sec)
	}
}

// allow enregistre une requête pour la clé donnée et indique si elle est autorisée.
pub fn (mut rl RateLimiter) allow(key string) bool {
	now := time.now()
	rl.mu.lock()
	defer {
		rl.mu.unlock()
	}
	// Purge périodique des verrous obsolètes
	if rl.buckets.len >= max_buckets {
		for k, mut b in rl.buckets {
			if now.unix() - b.window_at.unix() >= rl.window_sec {
				rl.buckets.delete(k)
			}
		}
	}
	mut b := rl.buckets[key] or {
		Bucket{
			count: 0
			window_at: now
		}
	}
	if now.unix() - b.window_at.unix() >= rl.window_sec {
		b.count = 0
		b.window_at = now
	}
	if b.count < rl.max_events {
		b.count++
		rl.buckets[key] = b
		return true
	}
	return false
}
