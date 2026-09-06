module main

import veb
import common
import repository
import api
import services
import data

fn main() {
	config := common.load_config()
	services.init_log_level(config.log_level)

	services.log_info('=================================')
	services.log_info('  KPay - Système de Paie v0.1.0')
	services.log_info('=================================')
	services.log_info('Environment: ${config.environment}')
	services.log_info('Database: ${config.db_host}:${config.db_port}/${config.db_name}')

	// Fail-fast : une méthode d'authentification est obligatoire
	if config.api_key.len == 0 && config.jwt_secret.len == 0 {
		services.log_error("Aucune méthode d'auth configurée — définissez KPAY_API_KEY ou KPAY_JWT_SECRET dans .env")
		return
	}
	if config.jwt_secret.len > 0 {
		services.log_info('Auth: JWT actif')
	} else {
		services.log_info('Auth: API Key active (compatibilité)')
	}

	mut repo := repository.new_repository(config) or {
		services.log_error('Erreur connexion DB: ${err}')
		return
	}

	services.log_info('Base de données initialisée')

	storage_svc := services.new_storage_service(config)
	services.log_info('Stockage MinIO configuré (bucket: ${config.minio_bucket})')

	// Limiteur de débit (désactivable avec KPAY_RATE_LIMIT_MAX=0)
	mut rate_limiter := &common.RateLimiter(unsafe { nil })
	if config.rate_limit_max > 0 {
		rate_limiter = common.new_rate_limiter(config.rate_limit_max, config.rate_limit_window)
		services.log_info('Rate limiting: ${config.rate_limit_max} req / ${config.rate_limit_window}s par IP')
	}

	// Service d'envoi d'emails (SMTP)
	mailer_svc := services.new_mailer_service(config)
	if config.smtp_enabled {
		services.log_info('SMTP activé (${config.smtp_host}:${config.smtp_port}, TLS: ${config.smtp_ssl || config.smtp_starttls})')
	} else {
		services.log_info('SMTP désactivé — notifications journalisées uniquement (KPAY_SMTP_ENABLED=true pour activer)')
	}

	// Journal d'audit
	audit_svc := services.new_audit_service(mut repo)

	// Pool de connexions PostgreSQL
	services.log_info('Pool DB: max_open=${config.db_pool_max_open} max_idle=${config.db_pool_max_idle} lifetime=${config.db_pool_conn_max_lifetime}s (GET /health/db pour les stats)')

	mut app := &api.App{
		repo: repo
		api_key: config.api_key
		jwt_secret: config.jwt_secret
		cors_origins: config.cors_origins
		rate_limiter: rate_limiter
		employee_svc: services.new_employee_service(mut repo)
		contract_svc: services.new_contract_service(mut repo)
		payroll_svc: services.new_payroll_service(mut repo)
		storage_svc: storage_svc
		auth_svc: services.new_auth_service(mut repo, config)
		admin_svc: services.new_admin_service(mut repo)
		audit_svc: audit_svc
		mailer_svc: mailer_svc
		profile_svc: services.new_profile_service(mut repo)
	}
	app.payroll_svc.set_mailer(mailer_svc)

	// Enregistrement du middleware de logging de requêtes puis d'authentification
	app.use(handler: app.request_logger)
	app.use(handler: app.auth_middleware)

	data.seed_data(mut app.repo)!

	services.log_info('Démarrage serveur sur le port ${config.port}...')
	services.log_info('API disponible sur http://localhost:${config.port}')
	services.log_info('Documentation Swagger disponible sur http://localhost:${config.port}/docs')
	services.log_info('')
	services.log_info('Endpoints:')
	services.log_info('  POST /auth/login - Connexion (JWT)')
	services.log_info('  POST /auth/register - Création de compte employee (org 1)')
	services.log_info('  POST /admin/organizations - Créer une organisation + admin (plateforme)')
	services.log_info('  GET  /admin/organizations - Liste des organisations (plateforme)')
	services.log_info('  GET  /           - Info API')
	services.log_info('  GET  /health     - Health check')
	services.log_info('  GET  /health/db  - Statut du pool DB (admin)')
	services.log_info("  GET  /audit-logs - Journal d'audit (admin, filtres: &actor=&action=&resource=)")
	services.log_info('  GET  /docs       - Documentation Swagger UI')
	services.log_info('  GET  /openapi.yaml - Spécification OpenAPI 3.0')
	services.log_info('  GET  /employees  - Liste employés (paginé: ?page=&limit=)')
	services.log_info('  POST /employees  - Créer employé')
	services.log_info('  PUT  /employees/:id - Mettre à jour employé')
	services.log_info('  DELETE /employees/:id - Désactiver employé')
	services.log_info('  GET  /contracts/:employee_id - Contrat actif')
	services.log_info('  GET  /employees/:id/contracts - Historique contrats')
	services.log_info('  POST /contracts  - Créer contrat')
	services.log_info('  GET/POST /timesheets, /timesheets/:id (PUT/DELETE)')
	services.log_info('  GET/POST /adjustments, /adjustments/:id (PUT/DELETE)')
	services.log_info('  GET/POST /tax-rules, /tax-rules/:id (PUT)')
	services.log_info('  GET  /employees/:id/timesheets - Timesheet employé')
	services.log_info('  GET  /employees/:id/adjustments - Ajustements employé')
	services.log_info('  GET  /employees/:id/payslips - Bulletins employé')
	services.log_info('  GET  /payslips?month=&year= - Liste bulletins')
	services.log_info('  POST /payroll/calculate - Calculer paie')
	services.log_info('  POST /payroll/run       - Générer & sauvegarder la paie mensuelle')
	services.log_info('  GET  /payslips/:id      - Consulter un bulletin (JSON)')
	services.log_info('  GET  /payslips/:id/pdf  - Télécharger un bulletin (PDF)')
	services.log_info('  POST /payslips/:id/pay  - Marquer un bulletin payé')
	services.log_info('  POST /payslips/:id/submit  - Soumettre un bulletin (workflow)')
	services.log_info('  POST /payslips/:id/approve - Approuver un bulletin (workflow)')
	services.log_info('  POST /payslips/:id/reject  - Rejeter un bulletin (workflow)')
	services.log_info('  POST /me/profile          - Demander une modification du profil (ESS, validation RH)')
	services.log_info('  GET  /me/profile-requests - Historique des demandes (ESS)')
	services.log_info('  GET  /profile-changes     - Demandes de modification (RH, &status=)')
	services.log_info('  POST /profile-changes/:id/approve - Valider et appliquer (RH)')
	services.log_info('  POST /profile-changes/:id/reject  - Refuser avec motif (RH)')

	veb.run[api.App, api.Context](mut app, config.port)
}
