-- Pilier 1.2 — Workflow congés 2 niveaux (N+1 → RH), soldes annuels, justificatif maladie
-- Hiérarchie manager
ALTER TABLE employee ADD COLUMN IF NOT EXISTS manager_id INT;

-- Workflow de validation N+1 → RH
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT '';
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_by_mgr TEXT DEFAULT '';
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_at_mgr TIMESTAMP;
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP;
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS justificatif_path TEXT DEFAULT '';

-- Soldes de congés par employé/année/type
CREATE TABLE IF NOT EXISTS leave_balance (
    id SERIAL PRIMARY KEY,
    organization_id INT DEFAULT 1,
    employee_id INT NOT NULL,
    year INT NOT NULL,
    leave_type TEXT NOT NULL DEFAULT 'conge_paye',
    accrued_days REAL NOT NULL DEFAULT 0,
    used_days REAL NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_leave_balance ON leave_balance (employee_id, year, leave_type);
CREATE INDEX IF NOT EXISTS idx_leave_balance_org ON leave_balance (organization_id, employee_id);

-- Auto-rattachement : les employés sans manager rapportent au premier employé de
-- l'organisation (l'admin org par défaut). S'il n'existe qu'un seul employé, le
-- manager reste NULL et la validation N+1 est directement déléguée au RH.
UPDATE employee e
SET manager_id = (SELECT MIN(id) FROM employee WHERE organization_id = e.organization_id AND id <> e.id)
WHERE manager_id IS NULL
  AND EXISTS (SELECT 1 FROM employee o WHERE o.organization_id = e.organization_id AND o.id <> e.id);