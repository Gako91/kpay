module models

import time

// Organization représente un tenant/entreprise client dans KPay.
pub struct Organization {
pub:
	id                             int @[primary; sql: serial]
	name                           string
	tax_id                         string
	currency                       string
	leave_carence_days             int @[default: 3]
	leave_declaration_deadline_days int @[default: 2]
	created_at                     ?time.Time
}
