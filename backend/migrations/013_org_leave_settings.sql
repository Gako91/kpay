-- Pilier 1.2 — Règles de carence et délai de déclaration configurables par organisation
-- leave_carence_days : jours de carence non rémunérés appliqués à un congé maladie (réglement interne).
-- leave_declaration_deadline_days : délai maximum après la date de début pour déclarer une absence maladie.

ALTER TABLE organization ADD COLUMN IF NOT EXISTS leave_carence_days INT NOT NULL DEFAULT 3;
ALTER TABLE organization ADD COLUMN IF NOT EXISTS leave_declaration_deadline_days INT NOT NULL DEFAULT 2;