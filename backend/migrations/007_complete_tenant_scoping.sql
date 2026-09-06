-- Migration 007: Scope Multi-Tenancy complet (toutes les tables métier)
-- Les tables utilisées par l'ORM V sont contract, taxrule, timesheet, adjustment,
-- leaverequest et audit_log (cf. noms dérivés des modèles V).

ALTER TABLE contract ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE timesheet ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE adjustment ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE leaverequest ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS organization_id INT DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_contract_org ON contract(organization_id);
CREATE INDEX IF NOT EXISTS idx_taxrule_org ON taxrule(organization_id);
CREATE INDEX IF NOT EXISTS idx_timesheet_org ON timesheet(organization_id);
CREATE INDEX IF NOT EXISTS idx_adjustment_org ON adjustment(organization_id);
CREATE INDEX IF NOT EXISTS idx_leaverequest_org ON leaverequest(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_org ON audit_log(organization_id);