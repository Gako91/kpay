module dto

// LoginRequest - Corps de la requête de connexion
pub struct LoginRequest {
pub mut:
	username string
	password string
}

// RegisterRequest - Corps de la requête de création d'un utilisateur
pub struct RegisterRequest {
pub mut:
	username        string
	password        string
	email           string
	role            string
	organization_id int
}

// LoginResponse - Réponse de connexion avec token JWT
pub struct LoginResponse {
pub mut:
	success bool
	token   string
	sub     string
	role    string
	org     int
	expires string
}

// AuthUser est renvoyé en JSON après authentification (sans le hash).
pub struct AuthUser {
pub mut:
	id       int
	username string
	role     string
	email    string
}
