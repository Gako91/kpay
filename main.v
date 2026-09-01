module main

import veb
import common
import repository
import api
import services
import data

fn main() {
	config := common.load_config()

	services.log_info('=================================')
	services.log_info('  KPay - Système de Paie v0.1.0')
	services.log_info('=================================')
	services.log_info('Environment: ${config.environment}')
	services.log_info('Database: ${config.db_host}:${config.db_port}/${config.db_name}')

	// Fail-fast : la clé API est obligatoire
	if config.api_key.len == 0 {
		services.log_error('KPAY_API_KEY non défini — arrêt du serveur (définissez cette variable dans .env)')
		return
	}
	services.log_info('Auth: API Key active')

	mut repo := repository.new_repository(config) or {
		services.log_error('Erreur connexion DB: ${err}')
		return
	}

	services.log_info('Base de données initialisée')

	mut app := &api.App{
		repo: repo
		api_key: config.api_key
		employee_svc: services.new_employee_service(mut repo)
		contract_svc: services.new_contract_service(mut repo)
	}

	// Enregistrement du middleware d'authentification (s'applique à toutes les routes)
	app.use(handler: app.auth_middleware)

	data.seed_data(mut app.repo)!

	services.log_info('Démarrage serveur sur le port ${config.port}...')
	services.log_info('API disponible sur http://localhost:${config.port}')
	services.log_info('')
	services.log_info('Endpoints:')
	services.log_info('  GET  /           - Info API')
	services.log_info('  GET  /health     - Health check')
	services.log_info('  GET  /employees  - Liste employés')
	services.log_info('  POST /employees  - Créer employé')
	services.log_info('  GET  /contracts/:employee_id - Contrat actif')
	services.log_info('  POST /contracts  - Créer contrat')
	services.log_info('  POST /payroll/calculate - Calculer paie')
	services.log_info('  POST /payroll/run       - Générer & sauvegarder la paie mensuelle')
	services.log_info('  GET  /payslips/:id      - Consulter un bulletin (JSON)')
	services.log_info('  GET  /payslips/:id/pdf  - Télécharger un bulletin (PDF)')
	services.log_info('  POST /payslips/:id/pay  - Marquer un bulletin payé')

	veb.run[api.App, api.Context](mut app, config.port)
}
