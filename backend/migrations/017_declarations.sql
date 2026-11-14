-- Migration 017 : déclarations sociales (Pilier 5.1 — DISA CNPS)
--
-- 1. Données déclaratives de l'employé : n° CNPS, date de naissance, périodicité.
-- 2. Registre des déclarations scellées (empreinte du fichier + chaînage par organisation).
-- 3. Permission declaration.export (gestionnaire de paie et comptable ; admin implicite).

ALTER TABLE employee ADD COLUMN IF NOT EXISTS cnps_number TEXT DEFAULT '';
ALTER TABLE employee ADD COLUMN IF NOT EXISTS birth_date TEXT DEFAULT '';
ALTER TABLE employee ADD COLUMN IF NOT EXISTS salary_type TEXT DEFAULT 'M';
UPDATE employee SET cnps_number = '' WHERE cnps_number IS NULL;
UPDATE employee SET birth_date = '' WHERE birth_date IS NULL;
UPDATE employee SET salary_type = 'M' WHERE salary_type IS NULL OR salary_type = '';

CREATE TABLE IF NOT EXISTS declaration_export (
    id              SERIAL PRIMARY KEY,
    organization_id INT    NOT NULL REFERENCES organization(id),
    kind            TEXT   NOT NULL,
    period          TEXT   NOT NULL,
    version         INT    NOT NULL,
    file_name       TEXT   NOT NULL,
    object_name     TEXT   NOT NULL,
    content_type    TEXT   NOT NULL,
    sha256          TEXT   NOT NULL,
    prev_hash       TEXT   NOT NULL DEFAULT '',
    chain_hash      TEXT   NOT NULL,
    row_count       INT    NOT NULL DEFAULT 0,
    total_amount    BIGINT NOT NULL DEFAULT 0,
    created_by      TEXT   NOT NULL DEFAULT '',
    sealed_at       TEXT   NOT NULL,
    UNIQUE (organization_id, kind, period, version)
);
CREATE INDEX IF NOT EXISTS idx_declaration_org ON declaration_export (organization_id, id DESC);

-- Registre en ajout seul : les entrées scellées ne se modifient ni ne se suppriment.
CREATE OR REPLACE FUNCTION declaration_export_append_only() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'declaration_export est un registre scellé : % interdit', TG_OP;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_declaration_export_append_only ON declaration_export;
CREATE TRIGGER trg_declaration_export_append_only
    BEFORE UPDATE OR DELETE ON declaration_export
    FOR EACH ROW EXECUTE FUNCTION declaration_export_append_only();

INSERT INTO permission (code, label, module_name) VALUES
 ('declaration.export', 'Générer et consulter les déclarations sociales (DISA)', 'declaration')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permission (role, permission_code) VALUES
 ('payroll_officer', 'declaration.export'),
 ('accountant', 'declaration.export')
ON CONFLICT (role, permission_code) DO NOTHING;
