-- Migration 018 : détail figé des retenues de chaque bulletin.
--
-- Les lignes sont écrites dans la même transaction que le bulletin (génération
-- de paie) et remplacées lors d'un recalcul (bulletin en brouillon uniquement).
-- Les bulletins antérieurs à cette migration n'ont pas de lignes : le PDF
-- recalcule alors leur détail comme auparavant.

CREATE TABLE IF NOT EXISTS payslip_line (
    id              SERIAL PRIMARY KEY,
    organization_id INT    NOT NULL,
    payslip_id      INT    NOT NULL REFERENCES payslip(id) ON DELETE CASCADE,
    position        INT    NOT NULL DEFAULT 0,
    code            TEXT   NOT NULL DEFAULT '',
    label           TEXT   NOT NULL,
    share           TEXT   NOT NULL CHECK (share IN ('salarial', 'patronal')),
    base            BIGINT NOT NULL DEFAULT 0,
    rate            DOUBLE PRECISION NOT NULL DEFAULT 0,
    amount          BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_payslip_line_payslip ON payslip_line (payslip_id, position);
CREATE INDEX IF NOT EXISTS idx_payslip_line_org_code ON payslip_line (organization_id, code);
