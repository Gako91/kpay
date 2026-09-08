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