-- 009_profile_change_requests.sql
-- Bloc 1.1 #2 : mise à jour des informations personnelles avec validation RH.
-- L'employé demande une modification (RIB, BIC, téléphone, adresse, parts fiscales) ;
-- elle est appliquée au dossier employé uniquement après approbation par la RH.

ALTER TABLE employee ADD COLUMN IF NOT EXISTS phone TEXT DEFAULT '';
ALTER TABLE employee ADD COLUMN IF NOT EXISTS address TEXT DEFAULT '';

CREATE TABLE IF NOT EXISTS profile_change_request (
    id SERIAL PRIMARY KEY,
    organization_id INT DEFAULT 1,
    employee_id INT NOT NULL,
    field_name TEXT NOT NULL,
    old_value TEXT NOT NULL DEFAULT '',
    new_value TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'en_attente',
    rejection_reason TEXT NOT NULL DEFAULT '',
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_by TEXT NOT NULL DEFAULT '',
    reviewed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_profile_change_org_status ON profile_change_request (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_profile_change_employee ON profile_change_request (employee_id);