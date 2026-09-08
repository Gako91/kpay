module models

// LeaveBalance représente le solde annuel de congés d'un employé, cumulé par type
// (congé payé, RTT, maladie, sans solde). accrued_days est alimenté automatiquement
// en début de période (prorata pour les embauches en cours d'année) ; used_days est
// débité à la validation RH d'une demande.
@[table: 'leave_balance']
pub struct LeaveBalance {
pub:
	id              int @[primary; sql: serial]
	organization_id int @[default: 1]
	employee_id     int
	year            int
	leave_type      string
	accrued_days    f32 @[default: 0]
	used_days       f32 @[default: 0]
}