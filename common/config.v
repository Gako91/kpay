module common

import os

// Configuration de l'application
pub struct Config {
pub:
	port        int // Port du serveur HTTP
	db_host     string // Hôte PostgreSQL
	db_port     int // Port PostgreSQL
	db_user     string // Utilisateur PostgreSQL
	db_password string // Mot de passe PostgreSQL
	db_name     string // Nom de la base de données
	environment string // dev, staging, prod
	log_level   string // debug, info, warn, error
	api_key     string // Clé d'authentification API (header X-Api-Key)
	// MinIO / S3 Storage
	minio_endpoint   string // ex: http://minio:9000
	minio_access_key string
	minio_secret_key string
	minio_bucket     string // ex: payslips
}

// Charge les variables d'environnement depuis un fichier .env
pub fn load_dotenv(filepath string) {
	content := os.read_file(filepath) or { return }

	for line in content.split_into_lines() {
		trimmed := line.trim_space()
		// Ignorer les lignes vides et les commentaires
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}

		// Parser KEY=VALUE
		parts := trimmed.split_nth('=', 2)
		if parts.len == 2 {
			key := parts[0].trim_space()
			mut value := parts[1].trim_space()

			// Supprimer les guillemets simples ou doubles autour de la valeur
			if (value.starts_with("'") && value.ends_with("'")) || (value.starts_with('"') && value.ends_with('"')) {
				value = value[1..value.len - 1]
			}

			// Définir la variable d'environnement si elle n'existe pas déjà
			if os.getenv_opt(key) == none {
				os.setenv(key, value, true)
			}
		}
	}
}

// load_config Charge la configuration depuis les variables d'environnement
pub fn load_config() Config {
	// Charger le fichier .env si présent
	load_dotenv('.env')

	return Config{
		port: os.getenv_opt('KPAY_PORT') or { '8080' }.int()
		db_host: os.getenv_opt('KPAY_DB_HOST') or { 'localhost' }
		db_port: os.getenv_opt('KPAY_DB_PORT') or { '5432' }.int()
		db_user: os.getenv_opt('KPAY_DB_USER') or { 'kpay' }
		db_password: os.getenv_opt('KPAY_DB_PASSWORD') or { 'kpay' }
		db_name: os.getenv_opt('KPAY_DB_NAME') or { 'kpay_db' }
		environment: os.getenv_opt('KPAY_ENV') or { 'dev' }
		log_level: os.getenv_opt('KPAY_LOG_LEVEL') or { 'info' }
		api_key: os.getenv_opt('KPAY_API_KEY') or { '' }
		minio_endpoint: os.getenv_opt('MINIO_ENDPOINT') or { 'http://localhost:9000' }
		minio_access_key: os.getenv_opt('MINIO_ACCESS_KEY') or { 'minioadmin' }
		minio_secret_key: os.getenv_opt('MINIO_SECRET_KEY') or { 'minioadmin' }
		minio_bucket: os.getenv_opt('MINIO_BUCKET') or { 'payslips' }
	}
}

// is_dev Vérifie si on est en mode développement
pub fn (c Config) is_dev() bool {
	return c.environment == 'dev'
}

// is_prod Vérifie si on est en mode production
pub fn (c Config) is_prod() bool {
	return c.environment == 'prod'
}
