-- Migration 004: Journal d'audit + workflow d'approbation
CREATE TABLE IF NOT EXISTS audit_log (
    id SERIAL PRIMARY KEY,
    actor TEXT NOT NULL DEFAULT '',
    action TEXT NOT NULL DEFAULT '',
    resource TEXT NOT NULL DEFAULT '',
    resource_id BIGINT NOT NULL DEFAULT 0,
    detail TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE payslip ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'brouillon';
ALTER TABLE payslip ADD COLUMN IF NOT EXISTS approved_by TEXT DEFAULT '';
ALTER TABLE payslip ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP;
UPDATE payslip SET status = 'paye' WHERE is_paid = true AND status = 'brouillon';