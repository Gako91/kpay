module services

import crypto.sha256
import time
import models
import repository

// ==================== DISA (CNPS) — fichier d'entrée E-DISA ====================
//
// E-DISA attend un classeur Excel 97-2003 (.xls), sans ligne d'en-tête, à 9 colonnes :
//   A n° CNPS (12 chiffres)   B nom (majuscules, sans caractères spéciaux)
//   C prénoms                 D date de naissance (JJ/MM/AAAA)
//   E date d'embauche         F date de départ (vide si toujours en poste)
//   G périodicité M/J/H       H temps de travail sur l'année (mois, jours ou heures)
//   I salaire brut annuel (non plafonné, sans séparateurs)
//
// Seuls les bulletins validés (approuvé ou payé) sont déclarés. Une anomalie
// bloquante (donnée manquante ou mal formée, bulletin encore en attente) empêche
// le scellement : E-DISA rejetterait le fichier.

// SMIG mensuel (FCFA) : plancher d'assiette CNPS, utilisé pour un simple avertissement.
const disa_smig_monthly = i64(75000)

pub const disa_content_type = 'application/vnd.ms-excel'

// DisaRow est une ligne du fichier E-DISA (valeurs déjà formatées).
pub struct DisaRow {
pub:
	employee_id    int
	cnps_number    string
	last_name      string
	first_names    string
	birth_date     string // JJ/MM/AAAA
	hire_date      string // JJ/MM/AAAA
	departure_date string // JJ/MM/AAAA ou ''
	salary_type    string // M, J ou H
	work_time      f64
	annual_gross   i64
}

// DisaIssue est une anomalie détectée sur un salarié. blocking = empêche l'export.
pub struct DisaIssue {
pub:
	employee_id   int
	employee_name string
	field         string
	message       string
	blocking      bool
}

// DisaReport est le résultat de la préparation d'une DISA annuelle.
pub struct DisaReport {
pub:
	year           int
	rows           []DisaRow
	issues         []DisaIssue
	total_gross    i64
	blocking_count int
}

// DisaInput regroupe les données brutes d'une organisation pour une année.
pub struct DisaInput {
pub:
	year       int
	employees  []models.Employee
	contracts  []models.Contract
	payslips   []models.Payslip // bulletins dont la période commence dans l'année
	timesheets []models.Timesheet // relevés d'heures de l'année
}

fn is_validated_payslip(p models.Payslip) bool {
	return p.status in [models.status_approuve, models.status_paye] || p.is_paid
}

fn is_pending_payslip(p models.Payslip) bool {
	return !is_validated_payslip(p) && p.status != models.status_rejete
}

// disa_name met un nom au format E-DISA : majuscules ASCII, lettres et espaces
// uniquement (accents retirés, tirets et apostrophes remplacés par un espace).
pub fn disa_name(s string) string {
	upper := sanitize_pdf_text(s).to_upper()
	mut out := []u8{cap: upper.len}
	for c in upper.bytes() {
		ch := if c >= `A` && c <= `Z` {
			c
		} else if c in [` `, `-`, `'`, `\t`] {
			u8(` `)
		} else {
			continue
		}
		if ch == ` ` && (out.len == 0 || out.last() == ` `) {
			continue
		}
		out << ch
	}
	return out.bytestr().trim_space()
}

fn disa_issue(emp models.Employee, field string, message string, blocking bool) DisaIssue {
	return DisaIssue{
		employee_id: emp.id
		employee_name: '${emp.first_name} ${emp.last_name}'
		field: field
		message: message
		blocking: blocking
	}
}

fn disa_date(t time.Time) string {
	return t.custom_format('DD/MM/YYYY')
}

// build_disa prépare les lignes E-DISA et la liste des anomalies (fonction pure).
pub fn build_disa(input DisaInput) DisaReport {
	mut rows := []DisaRow{}
	mut issues := []DisaIssue{}
	mut total := i64(0)
	year_end := time.Time{
		year: input.year
		month: 12
		day: 31
	}

	for emp in input.employees {
		emp_slips := input.payslips.filter(it.employee_id == emp.id
			&& it.period_start.year == input.year)
		validated := emp_slips.filter(is_validated_payslip(it))
		pending := emp_slips.filter(is_pending_payslip(it))
		name := '${emp.first_name} ${emp.last_name}'
		if pending.len > 0 {
			issues << DisaIssue{
				employee_id: emp.id
				employee_name: name
				field: 'bulletins'
				message: '${pending.len} bulletin(s) de ${input.year} non validé(s) : approuver ou rejeter avant de déclarer'
				blocking: true
			}
		}
		if validated.len == 0 {
			continue
		}
		// A — n° CNPS
		if emp.cnps_number.len == 0 {
			issues << disa_issue(emp, 'cnps_number', 'N° CNPS manquant', true)
		} else if emp.cnps_number.len != 12 || !emp.cnps_number.bytes().all(it.is_digit()) {
			issues << disa_issue(emp, 'cnps_number', 'N° CNPS invalide (12 chiffres attendus)', true)
		}
		// B, C — nom et prénoms
		last_name := disa_name(emp.last_name)
		first_names := disa_name(emp.first_name)
		if last_name.len == 0 {
			issues << disa_issue(emp, 'last_name', 'Nom vide après normalisation', true)
		}
		if first_names.len == 0 {
			issues << disa_issue(emp, 'first_name', 'Prénoms vides après normalisation', true)
		}
		// D — date de naissance
		mut birth := ''
		if emp.birth_date.len == 0 {
			issues << disa_issue(emp, 'birth_date', 'Date de naissance manquante', true)
		} else {
			if t := time.parse_format(emp.birth_date, 'YYYY-MM-DD') {
				birth = disa_date(t)
			} else {
				issues << disa_issue(emp, 'birth_date', 'Date de naissance invalide (${emp.birth_date})', true)
			}
		}
		// E, F — embauche (premier contrat) et départ (fin du dernier contrat, si
		// tous les contrats sont clos au plus tard le 31/12 de l'année déclarée)
		contracts := input.contracts.filter(it.employee_id == emp.id && it.start_date.year > 1900)
		mut hire := ''
		mut departure := ''
		if contracts.len == 0 {
			issues << disa_issue(emp, 'contract', "Aucun contrat : date d'embauche inconnue", true)
		} else {
			mut first := contracts[0].start_date
			mut last_end := time.Time{}
			mut all_closed := true
			for c in contracts {
				if c.start_date < first {
					first = c.start_date
				}
				if end := c.end_date {
					if end > last_end {
						last_end = end
					}
				} else {
					all_closed = false
				}
			}
			hire = disa_date(first)
			if all_closed && last_end.year > 1900 && last_end <= year_end {
				departure = disa_date(last_end)
			}
		}
		// G, H — périodicité et temps de travail
		salary_type := if emp.salary_type.len == 0 { 'M' } else { emp.salary_type }
		mut work_time := f64(0)
		match salary_type {
			'M' {
				mut months := map[int]bool{}
				for p in validated {
					months[p.period_start.month] = true
				}
				work_time = f64(months.len)
			}
			'H' {
				for ts in input.timesheets {
					if ts.employee_id == emp.id && ts.year == input.year {
						work_time += f64(ts.hours_worked) + f64(ts.overtime_h)
					}
				}
				if work_time <= 0 {
					issues << disa_issue(emp, 'work_time', 'Salarié horaire sans relevé d’heures sur ${input.year}',
						true)
				}
			}
			'J' {
				issues << disa_issue(emp, 'salary_type', 'Périodicité journalière (J) non prise en charge : KPay ne suit pas les jours travaillés',
					true)
			}
			else {
				issues << disa_issue(emp, 'salary_type', 'Périodicité invalide (${salary_type})', true)
			}
		}
		// I — brut annuel
		mut gross := i64(0)
		for p in validated {
			gross += p.gross_amount
		}
		if salary_type == 'M' && gross < disa_smig_monthly * i64(work_time) {
			issues << disa_issue(emp, 'annual_gross', 'Brut annuel inférieur au SMIG × mois travaillés (E-DISA le signalera)',
				false)
		}
		total += gross
		rows << DisaRow{
			employee_id: emp.id
			cnps_number: emp.cnps_number
			last_name: last_name
			first_names: first_names
			birth_date: birth
			hire_date: hire
			departure_date: departure
			salary_type: salary_type
			work_time: work_time
			annual_gross: gross
		}
	}
	rows.sort_with_compare(fn (a &DisaRow, b &DisaRow) int {
		ka := '${a.last_name} ${a.first_names}'
		kb := '${b.last_name} ${b.first_names}'
		if ka < kb {
			return -1
		}
		if ka > kb {
			return 1
		}
		return a.employee_id - b.employee_id
	})
	return DisaReport{
		year: input.year
		rows: rows
		issues: issues
		total_gross: total
		blocking_count: issues.filter(it.blocking).len
	}
}

// disa_xls produit le fichier E-DISA (.xls, sans en-tête, 9 colonnes).
pub fn disa_xls(report DisaReport) ![]u8 {
	mut cells := [][]XlsCell{cap: report.rows.len}
	for r in report.rows {
		cells << [xls_text(r.cnps_number), xls_text(r.last_name), xls_text(r.first_names),
			xls_text(r.birth_date), xls_text(r.hire_date), xls_text(r.departure_date),
			xls_text(r.salary_type), xls_number(r.work_time), xls_number(f64(r.annual_gross))]
	}
	return generate_xls('DISA', cells)
}

// load_disa_input charge les données d'une organisation pour une année.
pub fn load_disa_input(repo &repository.Repository, year int, org_id int) DisaInput {
	return DisaInput{
		year: year
		employees: repo.get_all_employees_with_inactive(org_id)
		contracts: repo.get_all_contracts(org_id)
		payslips: repo.get_payslips_by_year(year, org_id)
		timesheets: repo.get_timesheets_by_year(year, org_id)
	}
}

// ==================== REGISTRE SCELLÉ ====================

// seal_declaration_file dépose le fichier dans MinIO puis l'inscrit au registre
// (empreinte SHA-256, version, chaînage). Le dépôt a lieu avant l'inscription :
// une entrée du registre a toujours son fichier.
pub fn seal_declaration_file(mut repo repository.Repository, storage &StorageService, org_id int, kind string, period string, base_name string, content_type string, data []u8, row_count int, total_amount i64, actor string) !models.DeclarationExport {
	digest := sha256.sum(data).hex()
	object_name := 'org_${org_id}/declarations/${kind}_${period}_${digest[..16]}.xls'
	storage.upload_file(object_name, data)!
	return repo.seal_declaration(models.DeclarationExport{
		organization_id: org_id
		kind: kind
		period: period
		file_name: base_name
		object_name: object_name
		content_type: content_type
		sha256: digest
		row_count: row_count
		total_amount: total_amount
		created_by: actor
		sealed_at: time.utc().format_rfc3339()
	})
}

// ChainCheck est le résultat de la vérification du registre d'une organisation.
pub struct ChainCheck {
pub:
	ok        bool
	entries   int
	broken_id int    // première entrée incohérente (0 si ok)
	reason    string // explication si !ok
}

// verify_declaration_chain recalcule le chaînage du registre (dans l'ordre de scellement).
pub fn verify_declaration_chain(chain []models.DeclarationExport) ChainCheck {
	mut prev := ''
	for d in chain {
		if d.prev_hash != prev {
			return ChainCheck{
				entries: chain.len
				broken_id: d.id
				reason: "Maillon précédent inattendu : une entrée antérieure a été supprimée ou modifiée"
			}
		}
		if models.declaration_chain_hash(prev, d) != d.chain_hash {
			return ChainCheck{
				entries: chain.len
				broken_id: d.id
				reason: 'Empreinte chaînée incorrecte : les métadonnées de cette entrée ont été modifiées'
			}
		}
		prev = d.chain_hash
	}
	return ChainCheck{
		ok: true
		entries: chain.len
	}
}
