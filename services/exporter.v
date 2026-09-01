module services

import os
import json2
import strings
import models
import core
import pdf

// ==================== HELPERS PDF ====================

// format_fcfa formate un montant en FCFA avec séparateurs de milliers.
// Les montants du projet sont stockés directement en FCFA (ex: 400000 = 400 000 FCFA).
pub fn format_fcfa(amount i64) string {
	s := '${amount}'
	if s.len <= 3 {
		return '${s} FCFA'
	}
	mut result := ''
	mut count := 0
	for i := s.len - 1; i >= 0; i-- {
		if count > 0 && count % 3 == 0 {
			result = ' ' + result
		}
		result = s[i..i + 1] + result
		count++
	}
	return '${result} FCFA'
}

// sanitize_pdf_text remplace les caractères accentués par leurs équivalents ASCII
// afin de garantir un affichage correct avec les polices de base PDF (Latin-1 / Helvetica).
fn sanitize_pdf_text(s string) string {
	replacements := {
		'à': 'a'
		'â': 'a'
		'ä': 'a'
		'á': 'a'
		'ã': 'a'
		'å': 'a'
		'æ': 'ae'
		'è': 'e'
		'é': 'e'
		'ê': 'e'
		'ë': 'e'
		'ì': 'i'
		'í': 'i'
		'î': 'i'
		'ï': 'i'
		'ò': 'o'
		'ó': 'o'
		'ô': 'o'
		'õ': 'o'
		'ö': 'o'
		'ø': 'o'
		'ù': 'u'
		'ú': 'u'
		'û': 'u'
		'ü': 'u'
		'ý': 'y'
		'ÿ': 'y'
		'ñ': 'n'
		'ç': 'c'
		'œ': 'oe'
		'À': 'A'
		'Â': 'A'
		'Ä': 'A'
		'Á': 'A'
		'Ã': 'A'
		'Å': 'A'
		'Æ': 'AE'
		'È': 'E'
		'É': 'E'
		'Ê': 'E'
		'Ë': 'E'
		'Ì': 'I'
		'Í': 'I'
		'Î': 'I'
		'Ï': 'I'
		'Ò': 'O'
		'Ó': 'O'
		'Ô': 'O'
		'Õ': 'O'
		'Ö': 'O'
		'Ø': 'O'
		'Ù': 'U'
		'Ú': 'U'
		'Û': 'U'
		'Ü': 'U'
		'Ý': 'Y'
		'Ñ': 'N'
		'Ç': 'C'
		'Œ': 'OE'
	}
	mut result := s
	for accent, ascii in replacements {
		result = result.replace(accent, ascii)
	}
	return result
}

// ===================== SEPA EXPORT ==================
// Structure pour le virement SEPA / bancaire
pub struct SepaTransfer {
pub:
	iban           string
	bic            string
	recipient_name string
	amount         i64
	reference      string
}

pub fn generate_sepa_xml(transfers []SepaTransfer) string {
	mut sb := strings.new_builder(1024)
	sb.write_string('<?xml version="1.0" encoding="UTF-8"?>\n')
	sb.write_string('<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">\n')

	for t in transfers {
		amount_fmt := f64(t.amount) / 100.0
		sb.write_string('\t<CdtTrfTxInf>\n')
		sb.write_string('\t\t<PmtId><EndToEndId>${t.reference}</EndToEndId></PmtId>\n')
		sb.write_string('\t\t<Amt><InstdAmt Ccy="XOF">${amount_fmt:.2f}</InstdAmt></Amt>\n')
		sb.write_string('\t\t<Cdtr><Nm>${t.recipient_name}</Nm></Cdtr>\n')
		sb.write_string('\t\t<CdtrAcct><Id><IBAN>${t.iban}</IBAN></Id></CdtrAcct>\n')
		sb.write_string('\t</CdtTrfTxInf>\n')
	}

	sb.write_string('</Document>')
	return sb.str()
}

// ==================== CSV EXPORT ====================
pub fn generate_employees_csv(employees []models.Employee) string {
	mut sb := strings.new_builder(512)
	sb.write_string('ID,First Name,Last Name,Email,Active\n')
	for e in employees {
		sb.write_string('${e.id},"${e.first_name}","${e.last_name}","${e.email}",${e.is_active}\n')
	}
	return sb.str()
}

pub fn export_employees_csv(employees []models.Employee, filepath string) ! {
	content := generate_employees_csv(employees)
	os.write_file(filepath, content)!
}

pub fn generate_payslips_csv(payslips []models.Payslip) string {
	mut sb := strings.new_builder(1024)
	sb.write_string('ID,EmployeeID,PeriodStart,PeriodEnd,GrossAmount,TotalTaxes,NetAmount,Paid\n')
	for p in payslips {
		sb.write_string('${p.id},${p.employee_id},"${p.period_start.format_ss()}","${p.period_end.format_ss()}",${p.gross_amount},${p.total_taxes},${p.net_amount},${p.is_paid}\n')
	}
	return sb.str()
}

pub fn export_payslips_csv(payslips []models.Payslip, filepath string) ! {
	content := generate_payslips_csv(payslips)
	os.write_file(filepath, content)!
}

// ==================== JSON EXPORT ====================
pub struct PayslipExport {
pub:
	employee_name  string
	period         string
	gross_amount   string
	total_taxes    string
	net_amount     string
	payment_status string
}

fn format_cents(cents i64) string {
	francs := cents / 100
	remaining := cents % 100
	return '${francs},${remaining:02d} FCFA'
}

pub fn payslip_to_export(p models.Payslip, employee_name string) PayslipExport {
	return PayslipExport{
		employee_name: employee_name
		period: '${p.period_start} - ${p.period_end}'
		gross_amount: format_cents(p.gross_amount)
		total_taxes: format_cents(p.total_taxes)
		net_amount: format_cents(p.net_amount)
		payment_status: if p.is_paid { 'Payé' } else { 'En attente' }
	}
}

pub fn export_payslip_json(p PayslipExport, filepath string) ! {
	content := json2.encode(p)
	os.write_file(filepath, content)!
}

// ==================== PDF EXPORT ====================

// pdf_dir est le répertoire de stockage des bulletins PDF générés.
const pdf_dir = 'storage/payslips'

// format_rate formate un taux en pourcentage (ex: 0.063 -> "6.30 %").
fn format_rate(rate f64) string {
	pct := rate * 100.0
	return '${pct:.2f} %'
}

// format_amount_clean formate un entier sans suffixe FCFA.
fn format_amount_clean(amount i64) string {
	s := '${amount}'
	if s.len <= 3 {
		return s
	}
	mut result := ''
	mut count := 0
	for i := s.len - 1; i >= 0; i-- {
		if count > 0 && count % 3 == 0 {
			result = ' ' + result
		}
		result = s[i..i + 1] + result
		count++
	}
	return result
}

// generate_payslip_pdf génère le bulletin de paie au format professionnel conforme aux standards CI/UEMOA.
pub fn generate_payslip_pdf(p models.Payslip, emp models.Employee, contract models.Contract, tax_details []core.TaxLine) ![]u8 {
	mut doc := pdf.Pdf{}
	doc.init()

	doc.use_base_font('Helvetica')
	doc.use_base_font('Helvetica-Bold')

	// Marges et limites de page (format A4 standard 210 x 297 mm)
	page_idx := doc.create_page(pdf.Page_params{
		format: 'A4'
		gen_content_obj: true
		compress: false
	})
	doc.page_list[page_idx].user_unit = pdf.mm_unit

	// Styles typographiques
	title_fnt := pdf.Text_params{
		font_size: 15.0
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.05, g: 0.15, b: 0.35 }
	}
	company_fnt := pdf.Text_params{
		font_size: 11.0
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.0, g: 0.2, b: 0.5 }
	}
	header_fnt := pdf.Text_params{
		font_size: 8.5
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.1, g: 0.1, b: 0.1 }
	}
	body_fnt := pdf.Text_params{
		font_size: 8.0
		font_name: 'Helvetica'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.15, g: 0.15, b: 0.15 }
	}
	body_bold := pdf.Text_params{
		font_size: 8.0
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.0, g: 0.0, b: 0.0 }
	}
	net_label_fnt := pdf.Text_params{
		font_size: 9.5
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.0, g: 0.0, b: 0.0 }
	}
	net_val_fnt := pdf.Text_params{
		font_size: 13.0
		font_name: 'Helvetica-Bold'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.0, g: 0.45, b: 0.2 }
	}
	footer_fnt := pdf.Text_params{
		font_size: 7.0
		font_name: 'Helvetica'
		s_color: pdf.RGB{ r: -1, g: -1, b: -1 }
		f_color: pdf.RGB{ r: 0.4, g: 0.4, b: 0.4 }
	}

	// ==================== 1. EN-TETE SOCIETE & TITRE ====================
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('KPAY PAYROLL SERVICES', 15, 282, company_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Systeme de Gestion & Paie Haute Performance', 15, 276, footer_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Abidjan - Cote d Ivoire', 15, 271, footer_fnt))

	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('BULLETIN DE PAIE', 125, 280, title_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Periode : ${p.period_start.format_ss()} au ${p.period_end.format_ss()}', 125, 273, body_bold))

	// ==================== 2. BLOCS INFORMATIONS (SOCIETE & SALARIE) ====================
	// Bloc Employeur (gauche)
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Convention : INTERPROFESSIONNELLE', 15, 260, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('N C.C. / RCCM : CI-ABJ-03-2024-B12', 15, 254, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('N CNPS Employeur : 12345678', 15, 248, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Horaire mensuel : 173.33 h', 15, 242, body_fnt))

	// Bloc Salarié (droite)
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Matricule : EMP-${emp.id:04d}', 115, 260, header_fnt))
	full_name := sanitize_pdf_text('${emp.first_name.to_upper()} ${emp.last_name.to_upper()}')
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Nom & Prenoms : ${full_name}', 115, 254, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Email : ${emp.email}', 115, 248, body_fnt))
	iban_str := if emp.iban.len > 0 { emp.iban } else { 'N/A' }
	bic_str := if emp.bic.len > 0 { emp.bic } else { 'N/A' }
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Paiement : Virement (${iban_str} / ${bic_str})', 115, 242, body_fnt))

	// ==================== 3. TABLEAU DES RUBRIQUES ====================
	mut table_y := f32(230.0)
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('N', 15, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Designation', 25, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Nombre/Base', 95, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Gain / Brut', 125, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Retenue Sal.', 148, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Taux Patr.', 172, table_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Retenue Patr.', 188, table_y, header_fnt))

	table_y -= 8.0

	// Ligne Salaire de base
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('100', 15, table_y, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('SALAIRE DE BASE', 25, table_y, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('30.00 j / 173.33 h', 95, table_y, body_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_amount_clean(p.gross_amount), 125, table_y, body_bold))
	table_y -= 6.0

	// Lignes de Cotisations
	mut total_patronal := i64(0)
	for i, line in tax_details {
		rubrique_code := '${400 + i * 10}'
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(rubrique_code, 15, table_y, body_fnt))
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(sanitize_pdf_text(line.name), 25, table_y, body_fnt))
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_amount_clean(p.gross_amount), 95, table_y, body_fnt))
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_amount_clean(line.amount), 148, table_y, body_fnt))

		patronal_amount := i64(f64(line.amount) * 1.87)
		total_patronal += patronal_amount
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('7.70 %', 172, table_y, body_fnt))
		doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_amount_clean(patronal_amount), 188, table_y, body_fnt))

		table_y -= 6.0
	}

	// ==================== 4. TOTAUX & RECAPITULATIF ====================
	totaux_y := f32(75.0)
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Total Brut', 15, totaux_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Cotis. Salariales', 55, totaux_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Cotis. Patronales', 100, totaux_y, header_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('Cout Total Global', 145, totaux_y, header_fnt))

	totaux_val_y := totaux_y - 6.0
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_fcfa(p.gross_amount), 15, totaux_val_y, body_bold))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_fcfa(p.total_taxes), 55, totaux_val_y, body_bold))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_fcfa(total_patronal), 100, totaux_val_y, body_bold))
	total_global := p.gross_amount + total_patronal
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_fcfa(total_global), 145, totaux_val_y, body_bold))

	// ==================== 5. ENCADRE NET A PAYER ====================
	net_box_y := f32(45.0)
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text('NET A PAYER', 145, net_box_y + 8.0, net_label_fnt))
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(format_fcfa(p.net_amount), 145, net_box_y, net_val_fnt))

	status_str := if p.is_paid { 'Statut : PAYE' } else { 'Statut : EN ATTENTE DE VIREMENT' }
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(status_str, 15, net_box_y, body_bold))

	// ==================== 6. PIED DE PAGE LEGAL ====================
	legal_text := 'Pour vous aider a faire valoir vos droits, conservez ce bulletin de paie sans limitation de duree.'
	doc.page_list[page_idx].push_content(doc.page_list[page_idx].draw_base_text(sanitize_pdf_text(legal_text), 15, 18, footer_fnt))

	return doc.render()!
}

// generate_and_store_payslip_pdf génère le PDF, le sauvegarde sur disque dans
// pdf_dir/bulletin_<payslip_id>.pdf, et retourne le chemin du fichier.
// Si le fichier existe déjà (pdf_path non vide dans le Payslip), il est renvoyé directement
// sans regénération (mise en cache simple par existence de fichier).
pub fn generate_and_store_payslip_pdf(p models.Payslip, emp models.Employee, contract models.Contract, tax_details []core.TaxLine) !string {
	filepath := '${pdf_dir}/bulletin_${p.id}.pdf'

	// Réutiliser le fichier existant si déjà généré
	if os.exists(filepath) {
		return filepath
	}

	// Créer le répertoire de stockage si nécessaire
	os.mkdir_all(pdf_dir) or {
		return error('Impossible de créer le dossier PDF (${pdf_dir}): ${err}')
	}

	pdf_bytes := generate_payslip_pdf(p, emp, contract, tax_details)!
	os.write_file_array(filepath, pdf_bytes) or {
		return error("Impossible d'écrire le fichier PDF (${filepath}): ${err}")
	}

	return filepath
}

// generate_and_store_payslip_pdf_minio génère le PDF, le sauvegarde dans MinIO et sur disque (cache)
pub fn generate_and_store_payslip_pdf_minio(p models.Payslip, emp models.Employee, contract models.Contract, tax_details []core.TaxLine, storage &StorageService) !string {
	object_key := 'bulletin_${p.id}.pdf'

	// Générer les octets du PDF
	pdf_bytes := generate_payslip_pdf(p, emp, contract, tax_details)!

	// Upload vers MinIO
	s3_key := storage.upload_file(object_key, pdf_bytes) or {
		services_log_warn('Upload MinIO échoué, fallback fichier local: ${err}')
		''
	}

	// Cache local optionnel
	os.mkdir_all(pdf_dir) or {}
	os.write_file_array('${pdf_dir}/${object_key}', pdf_bytes) or {}

	if s3_key.len > 0 {
		return s3_key
	}
	return '${pdf_dir}/${object_key}'
}

fn services_log_warn(msg string) {
	log_warn(msg)
}
