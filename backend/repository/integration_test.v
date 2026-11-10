module repository

// Tests d'intégration contre un vrai PostgreSQL.
//
// Activés par KPAY_TEST_DB_HOST (+ KPAY_TEST_DB_PORT/USER/PASSWORD/NAME). Sans cette
// variable, chaque test est ignoré, sauf si KPAY_TEST_REQUIRE_DB=1 (CI) : l'absence
// de base fait alors échouer la suite au lieu de passer silencieusement.
//
// Utiliser une base dédiée : les tests y créent des données (noms uniques par
// exécution, donc relançables sur la même base).
//
//   docker run -d --rm --name kpay-test-pg -p 127.0.0.1:5433:5432 \
//     -e POSTGRES_USER=kpay -e POSTGRES_PASSWORD=kpay -e POSTGRES_DB=kpay_test postgres:16-alpine
//   KPAY_TEST_DB_HOST=127.0.0.1 KPAY_TEST_DB_PORT=5433 v test repository/
import os
import time
import common
import models

fn open_test_db() ?Repository {
	host := os.getenv('KPAY_TEST_DB_HOST')
	if host == '' {
		assert os.getenv('KPAY_TEST_REQUIRE_DB') != '1', 'KPAY_TEST_REQUIRE_DB=1 mais KPAY_TEST_DB_HOST est vide'
		println('  (ignoré : KPAY_TEST_DB_HOST non défini)')
		return none
	}
	cfg := common.Config{
		db_host:          host
		db_port:          (os.getenv_opt('KPAY_TEST_DB_PORT') or { '5432' }).int()
		db_user:          os.getenv_opt('KPAY_TEST_DB_USER') or { 'kpay' }
		db_password:      os.getenv_opt('KPAY_TEST_DB_PASSWORD') or { 'kpay' }
		db_name:          os.getenv_opt('KPAY_TEST_DB_NAME') or { 'kpay_test' }
		db_pool_max_open: 5
		db_pool_max_idle: 2
	}
	// new_repository crée les tables et joue les migrations (dossier relatif au CWD)
	return new_repository(cfg) or { panic('connexion PostgreSQL de test impossible: ${err}') }
}

// uniq rend les noms uniques par exécution (base de test réutilisable).
fn uniq(prefix string) string {
	return '${prefix}_${time.now().unix_nano()}'
}

// new_test_org crée une organisation isolée et retourne son id.
fn new_test_org(mut r Repository) int {
	org_id, _ := r.create_organization_with_admin(models.Organization{
		name:     uniq('org')
		currency: 'XOF'
	}, models.User{
		username:  uniq('admin')
		role:      'admin'
		is_active: true
	}) or { panic(err) }
	return org_id
}

fn new_test_employee(org_id int) models.Employee {
	return models.Employee{
		organization_id: org_id
		first_name:      'Test'
		last_name:       'Integration'
		email:           '${uniq('emp')}@test.local'
		tax_parts:       1.0
		is_active:       true
	}
}

// Régression du bug V db.pg : via le pool, l'ORM retournait toujours 0 comme id.
fn test_insert_returns_real_ids() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	org_id := new_test_org(mut r)
	id1 := r.create_employee(new_test_employee(org_id))!
	id2 := r.create_employee(new_test_employee(org_id))!
	assert id1 > 0
	assert id2 > id1
	emp := r.get_employee_by_id(id2, org_id) or { panic('employé ${id2} introuvable') }
	assert emp.id == id2
	assert emp.organization_id == org_id
}

fn test_create_payslips_returns_ids() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	org_id := new_test_org(mut r)
	emp_id := r.create_employee(new_test_employee(org_id))!
	mut batch := []models.Payslip{}
	for m in 1 .. 4 {
		batch << models.Payslip{
			organization_id: org_id
			employee_id:     emp_id
			period_start:    time.Time{
				year:  2026
				month: m
				day:   1
			}
			period_end:      time.Time{
				year:  2026
				month: m
				day:   28
			}
			gross_amount:    400_000
			net_amount:      380_000
			status:          models.status_brouillon
		}
	}
	saved := r.create_payslips(batch)!
	assert saved.len == 3
	for p in saved {
		assert p.id > 0
		got := r.get_payslip_by_id(p.id, org_id) or { panic('bulletin ${p.id} introuvable') }
		assert got.employee_id == emp_id
	}
	assert saved[0].id != saved[1].id && saved[1].id != saved[2].id
}

// Une transaction annulée ne laisse rien en base (connexion réservée, pas le pool).
fn test_transaction_rollback() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	org_id := new_test_org(mut r)
	emp := new_test_employee(org_id)
	mut tx := r.begin()!
	id := sql tx {
		insert emp into models.Employee
	}!
	assert id > 0
	tx.rollback()!
	assert r.get_employee_by_id(id, org_id) == none
}

// Organisation + admin : tout ou rien, et username dupliqué refusé.
fn test_create_organization_with_admin() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	username := uniq('admin')
	org_id, user_id := r.create_organization_with_admin(models.Organization{
		name:     uniq('org')
		currency: 'XOF'
	}, models.User{
		username:  username
		role:      'admin'
		is_active: true
	})!
	assert org_id > 1
	assert user_id > 0
	user := r.get_user_by_username(username) or { panic('admin introuvable') }
	assert user.id == user_id
	assert user.organization_id == org_id

	orgs_before := r.get_all_organizations().len
	dup_name := uniq('org_dup')
	r.create_organization_with_admin(models.Organization{
		name: dup_name
	}, models.User{
		username: username
		role:     'admin'
	}) or {
		assert err.msg().contains('existe déjà')
		assert r.get_all_organizations().len == orgs_before
		assert r.get_organization_by_name(dup_name) == none
		return
	}
	assert false, 'un username dupliqué aurait dû être refusé'
}

// Isolation multi-tenant : un employé n'est jamais visible depuis une autre organisation.
fn test_tenant_isolation() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	org_a := new_test_org(mut r)
	org_b := new_test_org(mut r)
	emp_id := r.create_employee(new_test_employee(org_a))!
	assert r.get_employee_by_id(emp_id, org_a) != none
	assert r.get_employee_by_id(emp_id, org_b) == none
	assert r.get_all_employees(org_b).all(it.organization_id == org_b)
	assert !r.get_all_employees(org_b).any(it.id == emp_id)
}

// L'organisation plateforme (id 1) est garantie et idempotente ; la séquence est recalée.
fn test_ensure_platform_organization() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	r.ensure_platform_organization('KPay Platform', 'PLATFORM', 'XOF')!
	assert r.ensure_platform_organization('KPay Platform', 'PLATFORM', 'XOF')! == false
	platform := r.get_organization_by_id(1) or { panic('organisation 1 absente') }
	assert platform.id == 1
	assert new_test_org(mut r) > 1
}

// Les migrations sont rejouables sans erreur ni double application.
fn test_migrations_idempotent() ! {
	mut r := open_test_db() or { return }
	defer {
		r.close()
	}
	before := r.db.exec('SELECT version FROM schema_migrations')!.len
	r.run_migrations('migrations')!
	after := r.db.exec('SELECT version FROM schema_migrations')!.len
	assert after == before
	sql_files := os.ls('migrations')!.filter(it.ends_with('.sql'))
	assert after == sql_files.len
}
