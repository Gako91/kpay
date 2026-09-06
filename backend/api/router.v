module api

import veb
import dto
import repository
import services
import common
import models
import json2
import time

// import os

// Application principale
@[heap]
pub struct App {
	veb.Middleware[Context] // embedding en premier, sans modificateur
pub mut:
	repo         repository.Repository
	api_key      string // Clé API pour l'authentification (compatibilité)
	jwt_secret   string // Secret JWT
	cors_origins string // Origines CORS autorisées
	rate_limiter &common.RateLimiter = unsafe { nil } // Limiteur de débit par IP
	employee_svc services.EmployeeService // Service employés
	contract_svc services.ContractService // Service contrats
	payroll_svc  services.PayrollService // Service paie
	storage_svc  services.StorageService // Service stockage MinIO / S3
	auth_svc     services.AuthService // Service authentification
	admin_svc    services.AdminService // Service administration plateforme (tenants)
	audit_svc    services.AuditService // Service journal d'audit
	mailer_svc   services.MailerService // Service d'envoi d'emails (SMTP)
}

// Contexte par requête
pub struct Context {
	veb.Context
pub mut:
	user_sub  string // Identifiant de l'utilisateur authentifié (JWT sub)
	user_role string // Rôle de l'utilisateur authentifié
	user_org  int // Organisation (tenant) de l'utilisateur authentifié
}

// has_role vérifie que l'utilisateur courant possède l'un des rôles requis.
fn (ctx &Context) has_role(allowed_roles []string) bool {
	if ctx.user_role.len == 0 {
		return false
	}
	return allowed_roles.contains(ctx.user_role)
}

// ==================== MIDDLEWARE ====================

// PUBLIC_PATHS liste les routes accessibles sans authentification
const public_paths = ['/', '/health', '/health/liveness', '/health/readiness', '/metrics',
	'/openapi.yaml', '/docs', '/favicon.ico', '/auth/login', '/auth/register']

fn is_public(ctx Context) bool {
	for p in public_paths {
		if ctx.req.url == p {
			return true
		}
	}
	return false
}

// set_cors_headers applique les en-têtes CORS.
fn (app &App) set_cors_headers(mut ctx Context) {
	origin := ctx.req.header.get_custom('Origin') or { '' }
	if app.cors_origins == '*' || origin.len == 0 || app.cors_origins.split(',').map(it.trim_space()).contains(origin) {
		ctx.res.header.set_custom('Access-Control-Allow-Origin', if app.cors_origins == '*' {
			'*'
		} else {
			origin
		}) or {}
	}
	ctx.res.header.set_custom('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS') or {}
	ctx.res.header.set_custom('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Api-Key') or {}
	ctx.res.header.set_custom('Access-Control-Max-Age', '86400') or {}
}

// request_logger journalise chaque requête HTTP au niveau debug.
// Enregistré en premier pour s'exécuter avant l'authentification.
pub fn (app &App) request_logger(mut ctx Context) bool {
	body := ctx.req.data
	body_preview := if body.len > 0 {
		limit := if body.len > 256 { 256 } else { body.len }
		' body=${body[0..limit]}'
	} else {
		''
	}
	services.log_debug('→ ${ctx.req.method} ${ctx.req.url}${body_preview}')
	return true
}

// auth_middleware vérifie l'authentification JWT (Bearer) ou la clé API.
// Retourne true pour continuer, false pour bloquer (veb stoppe le handler).
pub fn (mut app App) auth_middleware(mut ctx Context) bool {
	app.set_cors_headers(mut ctx)

	// Répondre aux requêtes preflight CORS
	if ctx.req.method == .options {
		ctx.res.set_status(.no_content)
		return false
	}

	// Laisser passer les routes publiques
	if is_public(ctx) {
		return true
	}

	// Rate limiting par IP (autorise max_events requêtes par fenêtre)
	if app.rate_limiter != unsafe { nil } {
		client_ip := ctx.req.header.get_custom('X-Forwarded-For') or { 'local' }
		if !app.rate_limiter.allow(client_ip) {
			ctx.res.set_status(.too_many_requests)
			ctx.res.header.set_custom('Retry-After', '1') or {}
			ctx.json(dto.error_response('Trop de requêtes — veuillez réessayer plus tard'))
			return false
		}
	}

	// 1) Tenter l'authentification JWT via le header Authorization: Bearer <token>
	auth_header := ctx.req.header.get_custom('Authorization') or { '' }
	if auth_header.starts_with('Bearer ') {
		token := auth_header['Bearer '.len..].trim_space()
		claims := common.verify_jwt(token, app.jwt_secret) or {
			services.log_warn('Requête refusée — token JWT invalide (${ctx.req.url}): ${err}')
			ctx.res.set_status(.unauthorized)
			ctx.json(dto.error_response('Session invalide ou expirée'))
			return false
		}
		ctx.user_sub = claims.sub
		ctx.user_role = claims.role
		ctx.user_org = claims.org
		return true
	}

	// 2) Fallback : clé API (compatibilité / intégrations)
	// L'API key est associée à l'organisation par défaut (tenant 1).
	provided_key := ctx.req.header.get_custom('X-Api-Key') or { '' }
	if provided_key.len > 0 && provided_key == app.api_key {
		ctx.user_role = 'admin'
		ctx.user_org = 1
		return true
	}

	services.log_warn('Requête refusée — authentification manquante ou invalide (${ctx.req.url})')
	ctx.res.set_status(.unauthorized)
	ctx.json(dto.error_response('Authentification requise — fournissez un token Bearer JWT ou le header X-Api-Key'))
	return false
}

// OPENAPI_YAML_SPEC embarqué dans le binaire pour éviter les problèmes de chemin/conteneur
const openapi_yaml_spec = $embed_file('../openapi.yaml').to_string()

// audit_action enregistre une action dans le journal d'audit (best effort).
// L'acteur est l'utilisateur authentifié courant ('anonyme' pour les routes publiques).
pub fn (app &App) audit_action(mut ctx Context, action string, resource string, resource_id int, detail string) {
	actor := if ctx.user_sub.len > 0 { ctx.user_sub } else { 'anonyme' }
	ip := ctx.req.header.get_custom('X-Forwarded-For') or { '' }
	app.audit_svc.record(ctx.user_org, actor, action, resource, resource_id, detail, ip)
}

// ==================== ENDPOINTS ====================

// GET / - Info API
pub fn (app &App) index(mut ctx Context) veb.Result {
	return ctx.json(dto.ApiResponse{
		success: true
		data: 'KPay API v0.1.0'
		message: "Bienvenue sur l'API KPay"
	})
}

// health GET /health
@['/health']
pub fn (app &App) health(mut ctx Context) veb.Result {
	return ctx.text('OK')
}

// GET /health/liveness - Probe Kubernetes pour vérifier que l'application tourne
@['/health/liveness']
pub fn (app &App) health_liveness(mut ctx Context) veb.Result {
	return ctx.json({
		'status': 'UP'
	})
}

// health_readiness GET /health/readiness - Probe Kubernetes pour vérifier que la DB est connectée
@['/health/readiness']
pub fn (mut app App) health_readiness(mut ctx Context) veb.Result {
	db_ok := app.repo.ping()
	if !db_ok {
		ctx.res.set_status(.service_unavailable)
		return ctx.json({
			'status': 'DOWN'
			'reason': 'Base de données indisponible'
		})
	}
	return ctx.json({
		'status':   'UP'
		'database': 'CONNECTED'
	})
}

// metrics GET /metrics - Exposition des métriques de l'application au format Prometheus
@['/metrics']
pub fn (mut app App) metrics(mut ctx Context) veb.Result {
	stats := app.repo.pool_stats()
	mut body := "# HELP kpay_up Statut de l'application (1 = en ligne)\n"
	body += '# TYPE kpay_up gauge\n'
	body += 'kpay_up 1\n\n'

	body += '# HELP kpay_db_max_open_connections Nombre maximum de connexions ouvertes autorisees\n'
	body += '# TYPE kpay_db_max_open_connections gauge\n'
	body += 'kpay_db_max_open_connections ${stats.max_open_connections}\n\n'

	body += '# HELP kpay_db_open_connections Nombre de connexions ouvertes actuellement\n'
	body += '# TYPE kpay_db_open_connections gauge\n'
	body += 'kpay_db_open_connections ${stats.open_connections}\n\n'

	body += '# HELP kpay_db_in_use_connections Nombre de connexions actuellement utilisees\n'
	body += '# TYPE kpay_db_in_use_connections gauge\n'
	body += 'kpay_db_in_use_connections ${stats.in_use}\n\n'

	body += '# HELP kpay_db_idle_connections Nombre de connexions inactives\n'
	body += '# TYPE kpay_db_idle_connections gauge\n'
	body += 'kpay_db_idle_connections ${stats.idle}\n\n'

	body += "# HELP kpay_db_wait_count Nombre cumulatif d'attentes de connexions\n"
	body += '# TYPE kpay_db_wait_count counter\n'
	body += 'kpay_db_wait_count ${stats.wait_count}\n'

	ctx.res.header.set_custom('Content-Type', 'text/plain; version=0.0.4; charset=utf-8') or {}
	return ctx.text(body)
}

// health_db GET /health/db - État du pool de connexions PostgreSQL (réservé admin)
@['/health/db']
pub fn (mut app App) health_db(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	mut repo := app.repo
	stats := repo.pool_stats()
	payload := {
		'max_open_connections': int(stats.max_open_connections)
		'open_connections':     int(stats.open_connections)
		'in_use':               int(stats.in_use)
		'idle':                 int(stats.idle)
		'wait_count':           int(stats.wait_count)
	}
	return ctx.json(payload)
}

// get_audit_logs GET /audit-logs - Journal d'audit paginé et filtrable (réservé admin)
@['/audit-logs']
pub fn (app &App) get_audit_logs(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	page := if ctx.query['page'].len > 0 { ctx.query['page'].int() } else { 1 }
	if page < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'page' doit être >= 1"))
	}
	page_size := if ctx.query['limit'].len > 0 { ctx.query['limit'].int() } else { 50 }
	if page_size < 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Le paramètre 'limit' doit être >= 1"))
	}
	actor := if ctx.query['actor'].len > 0 { ctx.query['actor'] } else { '' }
	action := if ctx.query['action'].len > 0 { ctx.query['action'] } else { '' }
	resource := if ctx.query['resource'].len > 0 { ctx.query['resource'] } else { '' }

	logs, total := app.audit_svc.list(ctx.user_org, actor, action, resource, page, page_size)
	items := dto.PageResponse[models.AuditLog]{
		data: logs
		page: page
		page_size: page_size
		total: total
		total_pages: if page_size > 0 { (total + page_size - 1) / page_size } else { 0 }
	}
	return ctx.json(items)
}

// ==================== AUTH ====================

// auth_login POST /auth/login - Connexion et génération d'un token JWT
@['/auth/login'; post]
pub fn (mut app App) auth_login(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.LoginRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	res := app.auth_svc.login(req.username, req.password) or {
		app.audit_action(mut ctx, 'auth.login', 'user', 0, 'Échec de connexion pour ${req.username}: ${err}')
		ctx.res.set_status(.unauthorized)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'auth.login', 'user', 0, 'Connexion réussie pour ${req.username}')
	return ctx.json(res)
}

// auth_register POST /auth/register - Création d'un compte utilisateur
@['/auth/register'; post]
pub fn (mut app App) auth_register(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.RegisterRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	id := app.auth_svc.register(req.username, req.password, req.email) or {
		if err.msg().contains('existe déjà') {
			app.audit_action(mut ctx, 'auth.register', 'user', 0, "Échec — nom '${req.username}' déjà pris")
			ctx.res.set_status(.conflict)
			return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'auth.register', 'user', int(id), "Utilisateur '${req.username}' créé (employee, org 1)")
	ctx.res.set_status(.created)
	// services.log_info('Utilisateur ctx.re.data${ctx.req.data} ajouté')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Utilisateur créé' })
}

// favicon GET /favicon.ico
@['/favicon.ico']
pub fn (app &App) favicon(mut ctx Context) veb.Result {
	ctx.res.set_status(.no_content)
	return ctx.text('')
}

// openapi_spec GET /openapi.yaml - Spécification OpenAPI 3.0
@['/openapi.yaml']
pub fn (app &App) openapi_spec(mut ctx Context) veb.Result {
	ctx.res.header.set(.content_type, 'application/yaml; charset=utf-8')
	return ctx.text(openapi_yaml_spec)
}

// swagger_docs GET /docs - Interface Swagger UI interactive
@['/docs']
pub fn (app &App) swagger_docs(mut ctx Context) veb.Result {
	html := '<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>KPay API - Documentation Swagger</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  <style>
    body { margin: 0; padding: 0; background: #fafafa; }
  </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        url: "/openapi.yaml",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [
          SwaggerUIBundle.presets.apis,
          SwaggerUIStandalonePreset
        ],
        layout: "StandaloneLayout"
      });
    };
  </script>
</body>
</html>'
	return ctx.html(html)
}

// 404 Handler
pub fn (mut ctx Context) not_found() veb.Result {
	ctx.res.set_status(.not_found)
	return ctx.json(dto.error_response('Endpoint non trouvé'))
}
