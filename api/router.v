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
}

// Contexte par requête
pub struct Context {
	veb.Context
pub mut:
	user_sub  string // Identifiant de l'utilisateur authentifié (JWT sub)
	user_role string // Rôle de l'utilisateur authentifié
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
const public_paths = ['/', '/health', '/openapi.yaml', '/docs', '/favicon.ico', '/auth/login',
	'/auth/register']

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
		return true
	}

	// 2) Fallback : clé API (compatibilité / intégrations)
	provided_key := ctx.req.header.get_custom('X-Api-Key') or { '' }
	if provided_key.len > 0 && provided_key == app.api_key {
		ctx.user_role = 'admin'
		return true
	}

	services.log_warn('Requête refusée — authentification manquante ou invalide (${ctx.req.url})')
	ctx.res.set_status(.unauthorized)
	ctx.json(dto.error_response('Authentification requise — fournissez un token Bearer JWT ou le header X-Api-Key'))
	return false
}

// OPENAPI_YAML_SPEC embarqué dans le binaire pour éviter les problèmes de chemin/conteneur
const openapi_yaml_spec = $embed_file('../openapi.yaml').to_string()

// ==================== ENDPOINTS ====================

// GET / - Info API
pub fn (app &App) index(mut ctx Context) veb.Result {
	return ctx.json(dto.ApiResponse{
		success: true
		data: 'KPay API v0.1.0'
		message: "Bienvenue sur l'API KPay"
	})
}

// GET /health
@['/health']
pub fn (app &App) health(mut ctx Context) veb.Result {
	return ctx.text('OK')
}

// ==================== AUTH ====================

// POST /auth/login - Connexion et génération d'un token JWT
@['/auth/login'; post]
pub fn (app &App) auth_login(mut ctx Context) veb.Result {
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
		ctx.res.set_status(.unauthorized)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(res)
}

// POST /auth/register - Création d'un compte utilisateur
@['/auth/register'; post]
pub fn (app &App) auth_register(mut ctx Context) veb.Result {
	body := ctx.req.data
	req := json2.decode[dto.RegisterRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}

	id := app.repo.create_user(models.User{
		username: req.username
		password_hash: common.hash_password(req.password)
		role: req.role
		email: req.email
		is_active: true
		created_at: time.now()
	}) or {
		if err.msg().contains('existe déjà') {
			ctx.res.set_status(.conflict)
			return ctx.json(dto.ApiResponse{ success: false, data: '', message: err.msg() })
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	ctx.res.set_status(.created)
	// services.log_info('Utilisateur ctx.re.data${ctx.req.data} ajouté')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Utilisateur créé' })
}

// GET /favicon.ico
@['/favicon.ico']
pub fn (app &App) favicon(mut ctx Context) veb.Result {
	ctx.res.set_status(.no_content)
	return ctx.text('')
}

// GET /openapi.yaml - Spécification OpenAPI 3.0
@['/openapi.yaml']
pub fn (app &App) openapi_spec(mut ctx Context) veb.Result {
	ctx.res.header.set(.content_type, 'application/yaml; charset=utf-8')
	return ctx.text(openapi_yaml_spec)
}

// GET /docs - Interface Swagger UI interactive
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
