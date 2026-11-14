module repository

import db.pg
import models

// Verrou consultatif (pg_advisory_xact_lock) qui sérialise le scellement des
// déclarations d'une même organisation : sans lui, deux exports simultanés
// liraient le même maillon précédent et la chaîne bifurquerait.
const declaration_lock_class = 5101

// seal_declaration enregistre une déclaration au registre : attribue la version
// suivante pour (organisation, type, période), chaîne l'entrée à la précédente
// de l'organisation et l'insère, le tout dans une transaction.
pub fn (mut r Repository) seal_declaration(d models.DeclarationExport) !models.DeclarationExport {
	mut tx := r.begin()!
	sealed := seal_in_tx(mut tx, d) or {
		tx.rollback() or {}
		return err
	}
	tx.commit()!
	return sealed
}

fn seal_in_tx(mut tx pg.Tx, d models.DeclarationExport) !models.DeclarationExport {
	org := d.organization_id.str()
	tx.exec_param_many('SELECT pg_advisory_xact_lock(${declaration_lock_class}, \$1::int)',
		[org])!
	last := tx.exec_param_many('SELECT chain_hash FROM declaration_export WHERE organization_id = \$1 ORDER BY id DESC LIMIT 1',
		[org])!
	prev := if last.len > 0 { last[0].vals[0] or { '' } } else { '' }
	ver := tx.exec_param_many('SELECT COALESCE(MAX(version), 0) + 1 FROM declaration_export WHERE organization_id = \$1 AND kind = \$2 AND period = \$3',
		[org, d.kind, d.period])!
	version := (ver[0].vals[0] or { '1' }).int()

	base := models.DeclarationExport{
		...d
		version: version
		prev_hash: prev
	}
	sealed := models.DeclarationExport{
		...base
		chain_hash: models.declaration_chain_hash(prev, base)
	}
	rows := tx.exec_param_many('INSERT INTO declaration_export (organization_id, kind, period, version, file_name, object_name, content_type, sha256, prev_hash, chain_hash, row_count, total_amount, created_by, sealed_at) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13, \$14) RETURNING id',
		[org, sealed.kind, sealed.period, sealed.version.str(), sealed.file_name, sealed.object_name,
		sealed.content_type, sealed.sha256, sealed.prev_hash, sealed.chain_hash,
		sealed.row_count.str(), sealed.total_amount.str(), sealed.created_by, sealed.sealed_at])!
	id := (rows[0].vals[0] or { '0' }).int()
	return models.DeclarationExport{
		...sealed
		id: id
	}
}

// get_declarations liste le registre d'une organisation (plus récentes d'abord),
// filtré par type si kind est non vide.
pub fn (r &Repository) get_declarations(kind string, org_id int) []models.DeclarationExport {
	if kind.len > 0 {
		return sql r.db {
			select from models.DeclarationExport where organization_id == org_id && kind == kind order by id desc
		} or { [] }
	}
	return sql r.db {
		select from models.DeclarationExport where organization_id == org_id order by id desc
	} or { [] }
}

// get_declaration_chain retourne le registre d'une organisation dans l'ordre de scellement.
pub fn (r &Repository) get_declaration_chain(org_id int) []models.DeclarationExport {
	return sql r.db {
		select from models.DeclarationExport where organization_id == org_id order by id asc
	} or { [] }
}

pub fn (r &Repository) get_declaration_by_id(id int, org_id int) ?models.DeclarationExport {
	rows := sql r.db {
		select from models.DeclarationExport where id == id && organization_id == org_id limit 1
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}

// get_all_employees_with_inactive retourne tous les employés, y compris sortis :
// une déclaration annuelle couvre aussi les salariés partis en cours d'année.
pub fn (r &Repository) get_all_employees_with_inactive(org_id int) []models.Employee {
	return sql r.db {
		select from models.Employee where organization_id == org_id order by id asc
	} or { [] }
}

// get_payslips_by_year retourne les bulletins dont la période commence dans l'année.
pub fn (r &Repository) get_payslips_by_year(year int, org_id int) []models.Payslip {
	return sql r.db {
		select from models.Payslip where period_start >= start_of_month(1, year) && period_start <= end_of_month(12, year) && organization_id == org_id order by id asc
	} or { [] }
}

// get_timesheets_by_year retourne les relevés d'heures d'une année.
pub fn (r &Repository) get_timesheets_by_year(year int, org_id int) []models.Timesheet {
	return sql r.db {
		select from models.Timesheet where year == year && organization_id == org_id
	} or { [] }
}

// get_all_contracts retourne tous les contrats de l'organisation.
pub fn (r &Repository) get_all_contracts(org_id int) []models.Contract {
	return sql r.db {
		select from models.Contract where organization_id == org_id order by id asc
	} or { [] }
}
