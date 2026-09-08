module api

import models
import json2
import veb
import dto
import core
import time

// today_str retourne la date courante au format YYYY-MM-DD (date d'effet par défaut).
fn today_str() string {
	t := time.now()
	return '${t.year:04d}-${t.month:02d}-${t.day:02d}'
}

// is_active_default : si la requête ne précise pas explicitement 'is_active', la valeur
// décodée (false) vient du défaut struct, pas de l'intention API. On retombe alors sur le
// défaut de la colonne (TRUE), faute de quoi ce flag échapperait au contrôle de non-recouvrement.
fn is_active_default(body string, decoded_is_active bool) bool {
	if body.contains('"is_active"') {
		return decoded_is_active
	}
	return true
}

// ==================== COMPOSANTES ====================

// get_admin_tax_components GET /admin/tax-components - Liste des composantes de l'organisation
@['/admin/tax-components'; get]
pub fn (app &App) get_admin_tax_components(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	components := app.repo.get_components(ctx.user_org)
	return ctx.json(components)
}

// create_admin_tax_component POST /admin/tax-components - Créer une composante (versionnée)
@['/admin/tax-components'; post]
pub fn (mut app App) create_admin_tax_component(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxComponent](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	code := decoded.code.trim_space().to_upper()
	country := if decoded.country.len == 0 { 'CI' } else { decoded.country }
	eff_from := if decoded.effective_from.len == 0 { today_str() } else { decoded.effective_from }
	comp := models.TaxComponent{
		...decoded
		organization_id: ctx.user_org
		code: code
		country: country
		effective_from: eff_from
		is_active: is_active_default(body, decoded.is_active)
	}
	dto.validate_tax_component(comp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	new_id := app.repo.create_component(comp) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'admin.tax_component.create', 'tax_component', new_id, 'Création composante ${comp.code}')
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Composante créée' })
}

// update_admin_tax_component PUT /admin/tax-components/:id - Mettre à jour une composante
@['/admin/tax-components/:id'; put]
pub fn (mut app App) update_admin_tax_component(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'tax_component_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.get_component_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Composante non trouvée'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxComponent](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	comp := models.TaxComponent{
		...decoded
		id: id
		organization_id: ctx.user_org
		code: decoded.code.trim_space().to_upper()
		is_active: is_active_default(body, decoded.is_active)
	}
	dto.validate_tax_component(comp) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.update_component(comp, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'admin.tax_component.update', 'tax_component', id, 'Mise à jour composante ${comp.code}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Composante mise à jour' })
}

// ==================== TRANCHES ====================

// get_admin_tax_brackets GET /admin/tax-brackets - Liste des tranches de l'organisation
@['/admin/tax-brackets'; get]
pub fn (app &App) get_admin_tax_brackets(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	brackets := app.repo.get_brackets(ctx.user_org)
	return ctx.json(brackets)
}

// create_admin_tax_bracket POST /admin/tax-brackets - Créer une tranche (non-recouvrement vérifié)
@['/admin/tax-brackets'; post]
pub fn (mut app App) create_admin_tax_bracket(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxBracket](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	new_bracket := models.TaxBracket{
		...decoded
		organization_id: ctx.user_org
		is_active: is_active_default(body, decoded.is_active)
	}
	dto.validate_tax_bracket(new_bracket) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	existing := app.repo.get_brackets(ctx.user_org).filter(it.component_code == new_bracket.component_code && it.effective_from == new_bracket.effective_from && it.is_active)
	mut proposed := existing.clone()
	proposed << new_bracket
	dto.validate_brackets_no_overlap(proposed) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	new_id := app.repo.create_bracket(new_bracket) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'admin.tax_bracket.create', 'tax_bracket', new_id, 'Création tranche ${new_bracket.component_code} ${new_bracket.lower_bound}-${new_bracket.upper_bound}')
	ctx.res.set_status(.created)
	return ctx.json(dto.ApiResponse{ success: true, data: '${new_id}', message: 'Tranche créée' })
}

// update_admin_tax_bracket PUT /admin/tax-brackets/:id - Mettre à jour une tranche
@['/admin/tax-brackets/:id'; put]
pub fn (mut app App) update_admin_tax_bracket(mut ctx Context, id int) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	dto.validate_id(id, 'tax_bracket_id') or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.get_bracket_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Tranche non trouvée'))
	}
	body := ctx.req.data
	decoded := json2.decode[models.TaxBracket](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	updated := models.TaxBracket{
		...decoded
		id: id
		organization_id: ctx.user_org
		is_active: is_active_default(body, decoded.is_active)
	}
	dto.validate_tax_bracket(updated) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	siblings := app.repo.get_brackets(ctx.user_org).filter(it.component_code == updated.component_code && it.effective_from == updated.effective_from && it.is_active && it.id != id)
	mut overlap_check := siblings.clone()
	overlap_check << updated
	dto.validate_brackets_no_overlap(overlap_check) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.repo.update_bracket(updated, ctx.user_org) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response(err.msg()))
	}
	app.audit_action(mut ctx, 'admin.tax_bracket.update', 'tax_bracket', id, 'Mise à jour tranche ${updated.component_code}')
	return ctx.json(dto.ApiResponse{ success: true, data: '${id}', message: 'Tranche mise à jour' })
}

// ==================== IMPACT AVANT / APRÈS ====================

// compute_tax_impact POST /admin/tax-impact - Compare le net d'un salaire brut simulé
// entre la configuration actuelle de l'organisation et une configuration proposée.
@['/admin/tax-impact'; post]
pub fn (mut app App) compute_tax_impact(mut ctx Context) veb.Result {
	if !ctx.has_role(['admin', 'accountant']) {
		ctx.res.set_status(.forbidden)
		return ctx.json(dto.error_response('Accès refusé — rôle insuffisant'))
	}
	body := ctx.req.data
	req := json2.decode[dto.TaxImpactRequest](body) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	req.validate() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response(err.msg()))
	}
	period := if req.period.len > 0 { req.period } else { today_str() }
	pseudo := models.Contract{ base_salary: req.gross }

	cur_components := core.select_effective_components(app.repo.get_components(ctx.user_org), period)
	cur_brackets := core.select_effective_brackets(app.repo.get_brackets(ctx.user_org), period)
	current_res := core.compute_payslip_configurable(pseudo, cur_components, cur_brackets, [], req.tax_parts)

	// Config proposée : la moitié non fournie (composantes OU tranches) hérite de la
	// config courante — on peut ainsi simuler uniquement un changement de taux ou de barème.
	mut prop_components := cur_components.clone()
	if req.components.len > 0 {
		prop_components = core.select_effective_components(req.components, period)
	}
	mut prop_brackets := cur_brackets.clone()
	if req.brackets.len > 0 {
		prop_brackets = core.select_effective_brackets(req.brackets, period)
	}
	proposed_res := core.compute_payslip_configurable(pseudo, prop_components, prop_brackets, [], req.tax_parts)

	response := dto.TaxImpactResponse{
		current: dto.TaxImpactResult{
			net: current_res.net_pay
			taxes: current_res.total_taxes
			details: current_res.tax_details
		}
		proposed: dto.TaxImpactResult{
			net: proposed_res.net_pay
			taxes: proposed_res.total_taxes
			details: proposed_res.tax_details
		}
		delta_net: proposed_res.net_pay - current_res.net_pay
	}
	return ctx.json(response)
}