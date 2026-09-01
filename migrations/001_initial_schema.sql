module repository import db.pg import os import common import models / / Repository centralise l 'accès aux données PostgreSQL.
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
	repo.run_migrations(' migrations ') or {
		// Si le dossier n' existe pas ou en cas d 'erreur mineure, journaliser l' erreur } return repo } fn (mut r Repository) init_tables() ! { sql r.db { create table models.Employee create table models.Contract create table models.TaxRule create table models.Timesheet create table models.Adjustment create table models.Payslip } ! / / Auto - migration des colonnes IBAN / BIC sur la table existante employee r.db.exec(
    "ALTER TABLE employee ADD COLUMN IF NOT EXISTS iban TEXT DEFAULT '';"
)
or { } r.db.exec(
    "ALTER TABLE employee ADD COLUMN IF NOT EXISTS bic TEXT DEFAULT '';"
)
or { } } / / run_migrations applique les scripts SQL versionn é s depuis le dossier sp é cifi é.pub fn (mut r Repository) run_migrations(migrations_dir string) ! { if ! os.exists(migrations_dir) { return } / / Cr é ation de la table de suivi des migrations si elle n 'existe pas
	r.db.exec(' CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);') or {
		return error(' Impossible d \ 'initialiser schema_migrations: ${err}'
) } mut files: = os.ls(migrations_dir)
or { return } mut sql_files: = files.filter(it.ends_with('.sql')) sql_files.sort() for file in sql_files { / / V é rifier si la migration a d é j à é t é jou é e check_res: = r.db.exec_param_many(
    'SELECT version FROM schema_migrations WHERE version = $1;',
    [file]
)
or { return error('Erreur verification migration ${file}: ${err}') } if check_res.len > 0 { continue } file_path: = os.join_path(migrations_dir, file) sql_content: = os.read_file(file_path)
or { return error(
    'Impossible de lire la migration ${file_path}: ${err}'
) } r.begin_transaction()
or { return error('Erreur transaction migration ${file}: ${err}') } r.db.exec(sql_content)
or { r.rollback() return error('Erreur execution migration ${file}: ${err}') } r.db.exec_param_many(
    'INSERT INTO schema_migrations (version) VALUES ($1);',
    [file]
)
or { r.rollback() return error(
    'Erreur enregistrement migration ${file}: ${err}'
) } r.commit()
or { r.rollback() return error('Erreur commit migration ${file}: ${err}') } } } / / == == == == == == == == == == TRANSACTIONS == == == == == == == == == == / / begin_transaction d é marre une transaction PostgreSQL.pub fn (mut r Repository) begin_transaction() ! { r.db.exec('BEGIN')
or { return error('BEGIN échoué: ${err}') } } / / commit valide la transaction en cours.pub fn (mut r Repository) commit() ! { r.db.exec('COMMIT')
or { return error('COMMIT échoué: ${err}') } } / / rollback annule la transaction en cours.pub fn (mut r Repository) rollback() { r.db.exec('ROLLBACK')
or { } } / / == == == == == == == == == == UTILITIES == == == == == == == == == == pub fn (r & Repository) get_db() pg.DB { return r.db } pub fn (mut r Repository) close() { r.db.close()
or { } }

-- Migration 001: Initial Schema
CREATE TABLE IF NOT EXISTS employee (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    iban TEXT DEFAULT '',
    bic TEXT DEFAULT '',
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS contract (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    base_salary BIGINT NOT NULL,
    hourly_rate BIGINT NOT NULL,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP,
    currency TEXT DEFAULT 'XOF'
);

CREATE TABLE IF NOT EXISTS tax_rule (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    rate DOUBLE PRECISION NOT NULL,
    is_employer BOOLEAN NOT NULL,
    ceiling BIGINT DEFAULT 0,
    fixed_amount BIGINT DEFAULT 0,
    country TEXT DEFAULT 'CI'
);

CREATE TABLE IF NOT EXISTS timesheet (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    hours_worked REAL NOT NULL DEFAULT 0,
    overtime_h REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS adjustment (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    amount BIGINT NOT NULL,
    description TEXT NOT NULL,
    date TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS payslip (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
    period_start TIMESTAMP NOT NULL,
    period_end TIMESTAMP NOT NULL,
    gross_amount BIGINT NOT NULL,
    total_taxes BIGINT NOT NULL,
    net_amount BIGINT NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    paid_at TIMESTAMP,
    pdf_path TEXT DEFAULT ''
);
