module dto

// CreateOrganizationRequest - Corps de la requête de création d'une organisation (plateforme)
pub struct CreateOrganizationRequest {
pub mut:
	name           string
	tax_id         string
	currency       string
	admin_username string
	admin_password string
	admin_email    string
}

// CreateOrganizationResponse - Réponse après création d'une organisation + admin dédié
pub struct CreateOrganizationResponse {
pub mut:
	success        bool
	org_id         int
	name           string
	admin_username string
	message        string
}

// OrgLeaveSettingsInput - Paramétrage des règles de congés maladie par organisation
pub struct OrgLeaveSettingsInput {
pub mut:
	carence_days    int
	deadline_days   int
}

// validate vérifie les bornes des paramètres congés.
pub fn (i OrgLeaveSettingsInput) validate() ! {
	if i.carence_days < 0 || i.carence_days > 365 {
		return error('carence_days doit être compris entre 0 et 365')
	}
	if i.deadline_days < 0 || i.deadline_days > 365 {
		return error('deadline_days doit être compris entre 0 et 365')
	}
}

// RoleWithPermissions - Rôle avec la liste de ses permissions (RBAC).
pub struct RoleWithPermissions {
pub mut:
	role        string
	permissions []string
	builtin     bool
}

// RolePermissionsInput - Corps de la mise à jour des permissions d'un rôle.
pub struct RolePermissionsInput {
pub mut:
	permissions []string
}

// UserCreateInput - Création d'un compte utilisateur par un admin de l'organisation.
pub struct UserCreateInput {
pub mut:
	username string
	password string
	email    string
	role     string
}

pub fn (i UserCreateInput) validate() ! {
	if i.username.len < 3 {
		return error('username doit contenir au moins 3 caractères')
	}
	if i.password.len < 6 {
		return error('password doit contenir au moins 6 caractères')
	}
	if i.email.len < 5 || !i.email.contains('@') {
		return error('email invalide')
	}
	if !['admin', 'payroll_officer', 'accountant', 'manager', 'employee'].contains(i.role) {
		return error('rôle inconnu')
	}
}

// UserUpdateInput - Mise à jour du rôle / statut d'un compte.
pub struct UserUpdateInput {
pub mut:
	role      string
	is_active bool
}

pub fn (i UserUpdateInput) validate() ! {
	if !['admin', 'payroll_officer', 'accountant', 'manager', 'employee'].contains(i.role) {
		return error('rôle inconnu')
	}
}