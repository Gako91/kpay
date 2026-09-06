module api

import models
import json2
import veb
import dto

// GET /tax-rules?country=CI - Récupérer les règles fiscales
@['/tax-rules']
pub fn (app &App) get_tax_rules(mut ctx Context) veb.Result {
	country := ctx.query['country'] or { '' }
	rules := if country.len > 0 {
		app.repo.get_tax_rules(country, ctx.user_org)
	} else {
		app.repo.get_all_tax_rules(ctx.user_org)
	}
	return ctx.json(rules)
}

// POST /tax-rules - Créer une règle fiscale
@['/tax-rules'; post]
pub fn (mut app App) create_tax_rule(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxRule](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	rule := models.TaxRule{
		...decoded
		organization_id: ctx.user_org
	}
	if rule.name.trim_space().len < 2 || rule.rate < 0 || rule.rate > 1 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('Données de règle fiscale invalides'))
	}
	new_id := app.repo.create_tax_rule(rule) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Règle fiscale créée' })
}

// PUT /tax-rules/:id - Mettre à jour une règle fiscale
@['/tax-rules/:id'; put]
pub fn (mut app App) update_tax_rule(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'tax_rule_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxRule](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	rule := models.TaxRule{
		...decoded
		id: id
		organization_id: ctx.user_org
	}
	app.repo.get_tax_rule_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Règle fiscale non trouvée'))
	}
	app.repo.update_tax_rule(rule, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Règle fiscale mise à jour' })
}
