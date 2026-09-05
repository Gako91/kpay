module models

// Role définit les niveaux d'accès de l'application.
pub enum Role {
	admin
	payroll_officer
	accountant
	employee
}

// role_str convertit une chaîne en Role.
pub fn role_from_str(s string) !Role {
	return match s {
		'admin' { .admin }
		'payroll_officer' { .payroll_officer }
		'accountant' { .accountant }
		'employee' { .employee }
		else { error("Rôle inconnu: '${s}'") }
	}
}

// str retourne la représentation textuelle d'un rôle.
pub fn (r Role) str() string {
	return match r {
		.admin { 'admin' }
		.payroll_officer { 'payroll_officer' }
		.accountant { 'accountant' }
		.employee { 'employee' }
	}
}
