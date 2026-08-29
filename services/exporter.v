module services

import os
import json2
import strings
import models

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
		employee_name:  employee_name
		period:         '${p.period_start} - ${p.period_end}'
		gross_amount:   format_cents(p.gross_amount)
		total_taxes:    format_cents(p.total_taxes)
		net_amount:     format_cents(p.net_amount)
		payment_status: if p.is_paid { 'Payé' } else { 'En attente' }
	}
}

pub fn export_payslip_json(p PayslipExport, filepath string) ! {
	content := json2.encode(p)
	os.write_file(filepath, content)!
}

