module api

import veb
import dto
import repository
import services

// Application principale
@[heap]
pub struct App {
	veb.Middleware[Context] // embedding en premier, sans modificateur
pub mut:
	repo         repository.Repository
	api_key      string // Clé API pour l'authentification
	employee_svc services.EmployeeService // Service employés
	contract_svc services.ContractService // Service contrats
}

// Contexte par requête
pub struct Context {
	veb.Context
}

// ==================== MIDDLEWARE ====================

// PUBLIC_PATHS liste les routes accessibles sans authentification
const public_paths = ['/', '/health']

// auth_middleware vérifie la clé API sur chaque requête protégée.
// Retourne true pour continuer, false pour bloquer (veb stoppe le handler).
pub fn (mut app App) auth_middleware(mut ctx Context) bool {
	// Laisser passer les routes publiques
	for p in public_paths {
		if ctx.req.url == p {
			return true
		}
	}

	// Récupérer la clé depuis le header X-Api-Key
	provided_key := ctx.req.header.get_custom('X-Api-Key') or { '' }

	if provided_key.len == 0 {
		services.log_warn('Requête refusée — header X-Api-Key manquant (${ctx.req.url})')
		ctx.res.set_status(.unauthorized)
		ctx.json(dto.error_response('Authentification requise — fournissez le header X-Api-Key'))
		return false
	}

	if provided_key != app.api_key {
		services.log_warn('Requête refusée — clé API invalide (${ctx.req.url})')
		ctx.res.set_status(.unauthorized)
		ctx.json(dto.error_response('Clé API invalide'))
		return false
	}

	return true
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

// GET /health
@['/health']
pub fn (app &App) health(mut ctx Context) veb.Result {
	return ctx.text('OK')
}

// 404 Handler
pub fn (mut ctx Context) not_found() veb.Result {
	ctx.res.set_status(.not_found)
	return ctx.json(dto.error_response('Endpoint non trouvé'))
}
