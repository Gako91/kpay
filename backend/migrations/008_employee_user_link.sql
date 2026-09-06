-- 008_employee_user_link.sql
-- Lien compte utilisateur <-> dossier employé (ESS self-service).
-- user_id est la FK logique vers user.id (pas de contrainte FK stricte pour
-- rester souple avec les tenants existants).

ALTER TABLE employee ADD COLUMN IF NOT EXISTS user_id INT;

CREATE INDEX IF NOT EXISTS idx_employee_user ON employee (user_id);