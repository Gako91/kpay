module models

import time

// ProfileChangeRequest : demande de modification d'un champ du dossier employé,
// soumise par l'employé (ESS) et appliquée après approbation RH.
@[table: 'profile_change_request']
pub struct ProfileChangeRequest {
pub:
	id               int        @[primary; sql: serial]
	organization_id  int        @[default: 1]
	employee_id      int
	field_name       string
	old_value        string     @[default: '']
	new_value        string     @[default: '']
	status           string     @[default: 'en_attente'] // en_attente | approuve | refuse
	rejection_reason string     @[default: '']
	requested_at     time.Time
	reviewed_by      string     @[default: '']
	reviewed_at      ?time.Time
}