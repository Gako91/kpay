module api

import veb
import models
import dto
import services
import core
import os

// render_payslip_pdf génère (ou re-lit depuis MinIO/cache) le PDF d'un bulletin
// et le renvoie au client. L'appelant DOIT avoir préalablement vérifié le droit
// d'accès (scoping org + propriétaire pour l'ESS) — ce rendu ne fait que la
// résolution minimale par scoping org de l'accès courant.
pub fn (mut app App) render_payslip_pdf(mut ctx Context, id int) veb.Result {
	// Re-récupération du bulletin scoped par tenant (pas de vérif propriétaire
	// ici : elle appartient à l'appelant côté route).
	payslip := app.repo.get_payslip_by_id(id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Bulletin non trouvé'))
	}
	emp := app.repo.get_employee_by_id(payslip.employee_id, ctx.user_org) or {
		ctx.res.set_status(.not_found)
		return ctx.json(dto.error_response('Employé non trouvé'))
	}
	contract := app.repo.get_active_contract(emp.id, ctx.user_org) or {
		models.Contract{
			organization_id: ctx.user_org
			employee_id: emp.id
			base_salary: payslip.gross_amount
		}
	}
	cnps_rules := app.repo.get_tax_rules('CI', ctx.user_org)
	adjustments := app.repo.get_adjustments_for_period(emp.id, payslip.period_start.month, payslip.period_start.year, ctx.user_org)

	// Affichage basé sur les montants FIGÉS du bulletin (gross_amount, total_taxes, net_amount)
	// et non sur un recalcul complet. On ne recalcule que le détail des lignes de cotisations
	// (salariales + patronales) à partir des règles CNPS appliquées au brut figé.
	frozen_gross := payslip.gross_amount
	tax_details := core.calculate_pay_full_ci(contract, cnps_rules, adjustments, emp.tax_parts).tax_details
	employer_details, employer_total := core.calculate_employer_contributions_ci(cnps_rules, frozen_gross)

	// Objet MinIO préfixé par organisation pour assurer l'isolation des fichiers entre tenants
	object_name := 'org_${ctx.user_org}/bulletin_${id}.pdf'
	mut pdf_bytes := []u8{}

	// Tenter de récupérer depuis MinIO en priorité
	pdf_bytes = app.storage_svc.download_file(object_name) or {
		// Si absent de MinIO, générer le PDF et l'uploader vers MinIO
		gen_path := services.generate_and_store_payslip_pdf_minio(payslip, emp, contract, tax_details, employer_details, employer_total, object_name, &app.storage_svc) or {
			services.log_error('Erreur génération PDF bulletin ${id}: ${err}')
			ctx.res.set_status(.internal_server_error)
			return ctx.json(dto.error_response('Erreur lors de la génération du PDF'))
		}
		if payslip.pdf_path.len == 0 {
			app.repo.update_payslip_pdf_path(id, gen_path, ctx.user_org) or {
				services.log_warn('Impossible de mettre à jour pdf_path pour bulletin ${id}: ${err}')
			}
		}
		// Télécharger à nouveau ou lire depuis cache
		app.storage_svc.download_file(object_name) or {
			local_path := 'storage/payslips/${object_name}'
			os.read_file(local_path) or {
				ctx.res.set_status(.internal_server_error)
				return ctx.json(dto.error_response('Fichier PDF introuvable après génération'))
			}.bytes()
		}
	}

	if pdf_bytes.len == 0 {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(dto.error_response('Fichier PDF vide ou introuvable'))
	}

	ctx.res.header.set(.content_type, 'application/pdf')
	ctx.res.header.set_custom('Content-Disposition', 'inline; filename="bulletin_${id}.pdf"') or {}
	// send_response_to_client envoie les bytes bruts sous forme de string sans ré-encodage UTF-8
	return ctx.send_response_to_client('application/pdf', pdf_bytes.bytestr())
}