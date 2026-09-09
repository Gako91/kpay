module repository

import db.pg
import os
import time
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
		host: config.db_host
		port: config.db_port
		user: config.db_user
		password: config.db_password
		dbname: config.db_name
	}
	// Pool de connexions PostgreSQL — paramétrable via KPAY_DB_POOL_*
	conn_max_lifetime := if config.db_pool_conn_max_lifetime > 0 {
		time.second * config.db_pool_conn_max_lifetime
	} else {
		time.Duration(0)
	}
	mut db := pg.connect(conf_db, pg.PoolConfig{
		max_open_conns: config.db_pool_max_open
		max_idle_conns: config.db_pool_max_idle
		conn_max_lifetime: conn_max_lifetime
	})!

	mut repo := Repository{
		db: db
	}
	repo.init_tables()!
	repo.run_migrations('migrations') or {
		eprintln('ERREUR MIGRATIONS: ${err}')
	}
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
		create table models.User
		create table models.AuditLog
		create table models.LeaveRequest
		create table models.Organization
		create table models.LeaveBalance
	}!

	// Les tables de sécurité (permission, role_permission, user_sso, sso_state)
	// sont créées et seedées par la migration 014 — unique source de vérité
	// (contraintes UNIQUE / FOREIGN KEY correctes pour ON CONFLICT).

	// Auto-migrations pour faire évoluer le schéma PostgreSQL existant
	r.db.exec('ALTER TABLE employee ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE payslip ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE "user" ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	// Scope multi-tenant des tables restantes
	r.db.exec('ALTER TABLE contract ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE timesheet ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE adjustment ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec('ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;') or {}
	r.db.exec("ALTER TABLE employee ADD COLUMN IF NOT EXISTS iban TEXT DEFAULT '';") or {}
	r.db.exec("ALTER TABLE employee ADD COLUMN IF NOT EXISTS bic TEXT DEFAULT '';") or {}
	r.db.exec("ALTER TABLE employee ADD COLUMN IF NOT EXISTS phone TEXT DEFAULT '';") or {}
	r.db.exec("ALTER TABLE employee ADD COLUMN IF NOT EXISTS address TEXT DEFAULT '';") or {}
	r.db.exec("ALTER TABLE employee ADD COLUMN IF NOT EXISTS user_id INT;") or {}
	r.db.exec('ALTER TABLE employee ADD COLUMN IF NOT EXISTS tax_parts REAL DEFAULT 1.0;') or {}
	// Pilier 1.2 — hiérarchie manager + workflow congés 2 niveaux + justificatif
	r.db.exec('ALTER TABLE employee ADD COLUMN IF NOT EXISTS manager_id INT;') or {}
	r.db.exec("ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT '';") or {}
	r.db.exec("ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_by_mgr TEXT DEFAULT '';") or {}
	r.db.exec('ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_at_mgr TIMESTAMP;') or {}
	r.db.exec('ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP;') or {}
	r.db.exec("ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS justificatif_path TEXT DEFAULT '';") or {}
	r.db.exec('ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS ceiling BIGINT DEFAULT 0;') or {}
	r.db.exec('ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS fixed_amount BIGINT DEFAULT 0;') or {}
	// Workflow d'approbation des bulletins
	r.db.exec("ALTER TABLE payslip ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'brouillon';") or {}
	r.db.exec("ALTER TABLE payslip ADD COLUMN IF NOT EXISTS approved_by TEXT DEFAULT '';") or {}
	r.db.exec('ALTER TABLE payslip ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP;') or {}
	// Rétro-compatibilité : les bulletins déjà payés sont marqués 'paye'
	r.db.exec("UPDATE payslip SET status = 'paye' WHERE is_paid = true AND status = 'brouillon';") or {}
	// Pilier 1.2 — règles de carence & délai de déclaration du congé maladie par organisation (migration 013)
	r.db.exec('ALTER TABLE organization ADD COLUMN IF NOT EXISTS leave_carence_days INT NOT NULL DEFAULT 3;') or {}
	r.db.exec('ALTER TABLE organization ADD COLUMN IF NOT EXISTS leave_declaration_deadline_days INT NOT NULL DEFAULT 2;') or {}
	// Pilier 3 — MFA TOTP sur le compte (migration 014)
	r.db.exec("ALTER TABLE \"user\" ADD COLUMN IF NOT EXISTS mfa_secret TEXT DEFAULT '';") or {}
	r.db.exec('ALTER TABLE "user" ADD COLUMN IF NOT EXISTS mfa_enabled BOOLEAN DEFAULT FALSE;') or {}
	r.db.exec("ALTER TABLE \"user\" ADD COLUMN IF NOT EXISTS mfa_backup_codes TEXT DEFAULT '';") or {}
}

// run_migrations applique les scripts SQL versionnés depuis le dossier spécifié.

// run_migrations applique les scripts SQL versionnés depuis le dossier spécifié.
pub fn (mut r Repository) run_migrations(migrations_dir string) ! {
	if !os.exists(migrations_dir) {
		return
	}

	// Création de la table de suivi des migrations si elle n'existe pas
	r.db.exec('CREATE TABLE IF NOT EXISTS schema_migrations (
		version TEXT PRIMARY KEY,
		applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);') or {
		return error("Impossible d'initialiser schema_migrations: ${err}")
	}

	mut files := os.ls(migrations_dir) or { return }
	mut sql_files := files.filter(it.ends_with('.sql'))
	sql_files.sort()

	for file in sql_files {
		// Vérifier si la migration a déjà été jouée
		check_res := r.db.exec_param_many('SELECT version FROM schema_migrations WHERE version = \$1;', [
			file,
		]) or {
			return error('Erreur verification migration ${file}: ${err}')
		}
		if check_res.len > 0 {
			continue
		}

		file_path := os.join_path(migrations_dir, file)
		sql_content := os.read_file(file_path) or {
			return error('Impossible de lire la migration ${file_path}: ${err}')
		}

		r.begin_transaction() or { return error('Erreur transaction migration ${file}: ${err}') }
		r.db.exec(sql_content) or {
			r.rollback()
			return error('Erreur execution migration ${file}: ${err}')
		}
		r.db.exec_param_many('INSERT INTO schema_migrations (version) VALUES (\$1);', [
			file,
		]) or {
			r.rollback()
			return error('Erreur enregistrement migration ${file}: ${err}')
		}
		r.commit() or {
			r.rollback()
			return error('Erreur commit migration ${file}: ${err}')
		}
	}
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

// pool_stats expose l'état du pool de connexions PostgreSQL.
pub fn (mut r Repository) pool_stats() pg.PoolStats {
	return r.db.stats()
}

// ping vérifie la connectivité à la base de données.
pub fn (mut r Repository) ping() bool {
	res := r.db.exec('SELECT 1;') or { return false }
	return res.len > 0
}

pub fn (mut r Repository) close() {
	r.db.close() or {}
}
