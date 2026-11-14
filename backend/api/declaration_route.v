module api

import veb
import json2
import crypto.sha256
import dto
import models
import services

// Déclarations sociales (Pilier 5.1) : DISA CNPS et registre scellé des exports.
// Toutes les routes exigent la permission declaration.export.

// DisaRequest est le corps de POST /exports/disa.
struct DisaRequest {
	year int
}

// DisaPreview est la réponse de l'aperçu (et des refus pour anomalies).
struct DisaPreview {
	year           int
	employees      int
	total_gross    i64
	blocking_count int
	rows           []services.DisaRow
	issues         []services.DisaIssue
}

fn disa_preview(report services.DisaReport) DisaPreview {
	return DisaPreview{
		year: report.year
		employees: report.rows.len
		total_gross: report.total_gross
		blocking_count: report.blocking_count
		rows: report.rows
		issues: report.issues
	}
}

// DisaSealed est la réponse d'un export DISA scellé.
struct DisaSealed {
	declaration models.DeclarationExport
	warnings    []services.DisaIssue
}

fn deny_declarations(mut ctx Context) ?veb.Result {
	if ctx.has_permission('declaration.export') {
		return none
	}
	ctx.res.set_status(.forbidden)
	return ctx.json(dto.error_response('Accès refusé — permission declaration.export requise'))
}

// GET /exports/disa/preview?year=2026 — lignes E-DISA et anomalies, sans rien sceller.
@['/exports/disa/preview']
pub fn (app &App) disa_preview_endpoint(mut ctx Context) veb.Result {
	if r := deny_declarations(mut ctx) {
		return r
	}
	year := ctx.query['year'].int()
	if year < 2000 || year > 2100 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Paramètre 'year' invalide (2000-2100)"))
	}
	report := services.build_disa(services.load_disa_input(&app.repo, year, ctx.user_org))
	return ctx.json(disa_preview(report))
}

// POST /exports/disa {"year": 2026} — génère le fichier E-DISA (.xls) et le scelle au
// registre. 422 avec la liste des anomalies si une donnée bloquante manque.
@['/exports/disa'; post]
pub fn (mut app App) disa_export_endpoint(mut ctx Context) veb.Result {
	if r := deny_declarations(mut ctx) {
		return r
	}
	req := json2.decode[DisaRequest](ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response('JSON invalide'))
	}
	if req.year < 2000 || req.year > 2100 {
		ctx.res.set_status(.bad_request)
		return ctx.json(dto.error_response("Champ 'year' invalide (2000-2100)"))
	}
	report := services.build_disa(services.load_disa_input(&app.repo, req.year, ctx.user_org))
	if report.blocking_count > 0 {
		ctx.res.set_status(.unprocessable_entity)
		return ctx.json(disa_preview(report))
	}
	if report.rows.len == 0 {
		ctx.res.set_status(.unprocessable_entity)
		return ctx.json(dto.error_response('Aucun bulletin validé en ${req.year} : rien à déclarer'))
	}
	data := services.disa_xls(report) or {
		services.log_error('Génération DISA ${req.year}: ${err}')
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Erreur lors de la génération du fichier DISA'))
	}
	sealed := services.seal_declaration_file(mut app.repo, &app.storage_svc, ctx.user_org,
		models.declaration_disa, '${req.year}', 'DISA_${req.year}.xls', services.disa_content_type,
		data, report.rows.len, report.total_gross, ctx.user_sub) or {
		services.log_error('Scellement DISA ${req.year}: ${err}')
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response("Erreur lors de l'archivage de la déclaration"))
	}
	app.audit_action(mut ctx, 'declaration.disa', 'declaration', sealed.id, 'DISA ${req.year} v${sealed.version} : ${sealed.row_count} salariés, brut ${sealed.total_amount}, sha256 ${sealed.sha256}')
	ctx.res.set_status(.created)
	return ctx.json(DisaSealed{
		declaration: sealed
		warnings: report.issues
	})
}

// GET /exports/declarations?kind=disa — registre des déclarations scellées.
@['/exports/declarations']
pub fn (app &App) list_declarations_endpoint(mut ctx Context) veb.Result {
	if r := deny_declarations(mut ctx) {
		return r
	}
	return ctx.json(app.repo.get_declarations(ctx.query['kind'], ctx.user_org))
}

// GET /exports/declarations/verify — vérifie le chaînage du registre de l'organisation.
@['/exports/declarations/verify']
pub fn (app &App) verify_declarations_endpoint(mut ctx Context) veb.Result {
	if r := deny_declarations(mut ctx) {
		return r
	}
	check := services.verify_declaration_chain(app.repo.get_declaration_chain(ctx.user_org))
	if !check.ok {
		services.log_error('Registre des déclarations incohérent (org ${ctx.user_org}, entrée ${check.broken_id}) : ${check.reason}')
	}
	return ctx.json(check)
}

// GET /exports/declarations/:id/file — télécharge le fichier scellé après avoir
// vérifié son empreinte (409 si le fichier archivé ne correspond plus).
@['/exports/declarations/:id/file']
pub fn (app &App) declaration_file_endpoint(mut ctx Context, id int) veb.Result {
	if r := deny_declarations(mut ctx) {
		return r
	}
	d := app.repo.get_declaration_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Déclaration introuvable'))
	}
	data := app.storage_svc.download_file(d.object_name) or {
		services.log_error('Déclaration ${id} : fichier archivé illisible (${err})')
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Fichier archivé introuvable'))
	}
	if sha256.sum(data).hex() != d.sha256 {
		services.log_error('Déclaration ${id} : empreinte SHA-256 du fichier archivé différente du registre')
		ctx.res.set_status(.conflict)
		return ctx.json(dto.error_response("Intégrité compromise : le fichier archivé ne correspond pas à l'empreinte scellée"))
	}
	versioned := d.file_name.replace('.xls', '_v${d.version}.xls')
	ctx.res.header.set_custom('Content-Disposition', 'attachment; filename="${versioned}"') or {}
	ctx.res.header.set_custom('X-Content-SHA256', d.sha256) or {}
	return ctx.send_response_to_client(d.content_type, data.bytestr())
}
