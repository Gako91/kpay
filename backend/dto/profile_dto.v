module dto

// ProfileChangeInput : body POST /me/profile — demande de modification d'un champ.
pub struct ProfileChangeInput {
pub mut:
	field string
	value string
}

// ProfileRejectInput : body POST /profile-changes/:id/reject — motif de refus.
pub struct ProfileRejectInput {
pub mut:
	reason string
}