-- Migration 006: Support Multi-Tenancy (Organisations)
CREATE TABLE IF NOT EXISTS organization (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    tax_id TEXT DEFAULT '',
    currency TEXT DEFAULT 'XOF',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE employee ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE payslip ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_employee_org ON employee(organization_id);
CREATE INDEX IF NOT EXISTS idx_payslip_org ON payslip(organization_id);
