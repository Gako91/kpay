-- Pilier 4 — file de traitement asynchrone des jobs (paie de masse, etc.)
-- La table job est créée par l'ORM (init_tables) ; cette migration n'ajoute que
-- les index de lecture/listing (surveillance GET /jobs) et de purge.
CREATE INDEX IF NOT EXISTS idx_job_org_status ON job (organization_id, status);
CREATE INDEX IF NOT EXISTS idx_job_org_created ON job (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_type ON job (job_type);