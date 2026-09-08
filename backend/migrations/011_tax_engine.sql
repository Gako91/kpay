-- Pilier 2.2 — Moteur de règles fiscales dynamiques
-- Versionnage des règles par date d'effet (effective_from) pour stabilité des périodes passées.

ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS effective_from TIMESTAMPTZ;
ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE taxrule ADD COLUMN IF NOT EXISTS basis_type TEXT NOT NULL DEFAULT 'brut';

-- Modèle réel des cotisations : composantes (retraite, maladie, AMV, AT, PF, ...)
CREATE TABLE IF NOT EXISTS taxcomponent (
    id SERIAL PRIMARY KEY,
    organization_id INT NOT NULL DEFAULT 1,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    rate DOUBLE PRECISION NOT NULL DEFAULT 0,
    basis_type TEXT NOT NULL DEFAULT 'brut',
    cap BIGINT NOT NULL DEFAULT 0,
    fixed_amount BIGINT NOT NULL DEFAULT 0,
    share TEXT NOT NULL DEFAULT 'salarial',
    effective_from TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    country TEXT NOT NULL DEFAULT 'CI'
);
CREATE INDEX IF NOT EXISTS idx_taxcomponent_org_code ON taxcomponent (organization_id, code);

-- Tranches ITS/IGR : barème progressif paramétrable
CREATE TABLE IF NOT EXISTS taxbracket (
    id SERIAL PRIMARY KEY,
    organization_id INT NOT NULL DEFAULT 1,
    component_code TEXT NOT NULL,
    lower_bound BIGINT NOT NULL,
    upper_bound BIGINT NOT NULL DEFAULT -1,
    rate DOUBLE PRECISION NOT NULL DEFAULT 0,
    flat BIGINT NOT NULL DEFAULT 0,
    effective_from TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_taxbracket_org_code ON taxbracket (organization_id, component_code);