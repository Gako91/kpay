module models

import time

// Organization représente un tenant/entreprise client dans KPay.
pub struct Organization {
pub:
	id         int @[primary; sql: serial]
	name       string
	tax_id     string
	currency   string
	created_at ?time.Time
}
