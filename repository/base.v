module repository

import db.pg
import common
import models

// Repository centralise l'accès aux données PostgreSQL.
// Les méthodes sont réparties dans des fichiers par modèle.
pub struct Repository {
mut:
	db pg.DB
}

pub fn new_repository(config common.Config) !Repository {
	conf_db := pg.Config{
		host:     config.db_host
		port:     config.db_port
		user:     config.db_user
		password: config.db_password
		dbname:   config.db_name
	}
	mut db := pg.connect(conf_db, pg.PoolConfig{})!

	mut repo := Repository{
		db: db
	}
	repo.init_tables()!
	return repo
}

fn (mut r Repository) init_tables() ! {
	sql r.db {
		create table models.Employee
		create table models.Contract
		create table models.TaxRule
		create table models.Timesheet
		create table models.Adjustment
		create table models.Payslip
	}!
}

// ==================== TRANSACTIONS ====================

// begin_transaction démarre une transaction PostgreSQL.
pub fn (mut r Repository) begin_transaction() ! {
	r.db.exec('BEGIN') or { return error('BEGIN échoué: ${err}') }
}

// commit valide la transaction en cours.
pub fn (mut r Repository) commit() ! {
	r.db.exec('COMMIT') or { return error('COMMIT échoué: ${err}') }
}

// rollback annule la transaction en cours.
pub fn (mut r Repository) rollback() {
	r.db.exec('ROLLBACK') or {}
}

// ==================== UTILITIES ====================

pub fn (r &Repository) get_db() pg.DB {
	return r.db
}

pub fn (mut r Repository) close() {
	r.db.close() or {}
}
