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
	success       bool
	org_id        int
	name          string
	admin_username string
	message       string
}