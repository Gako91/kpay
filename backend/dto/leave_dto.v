module dto

// CreateMyLeaveInput — corps pour soumettre sa propre demande de congé (ESS).
pub struct CreateMyLeaveInput {
pub:
	leave_type string
	start_date string // YYYY-MM-DD
	end_date   string // YYYY-MM-DD
	days_count f32
	reason     string
}

// LeaveRejectInput — motif obligatoire pour un refus (N+1 ou RH).
pub struct LeaveRejectInput {
pub:
	reason string
}

// JustificatifInput — upload d'un justificatif (congé maladie), fichier base64.
pub struct JustificatifInput {
pub:
	filename string
	content  string // base64 du PDF
}