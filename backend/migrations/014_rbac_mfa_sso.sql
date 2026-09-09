-- Pilier 3 — RBAC fin (permissions granulaire) + MFA TOTP + SSO OIDC (liens de comptes)

-- ==================== RBAC ====================
-- Catalogue de permissions (granularité par action)
CREATE TABLE IF NOT EXISTS permission (
    code   TEXT PRIMARY KEY,
    label  TEXT NOT NULL,
    module_name TEXT NOT NULL DEFAULT 'general'
);

-- Mappage rôle → permissions (index unique composite, schema aligné sur le modèle ORM)
CREATE TABLE IF NOT EXISTS role_permission (
    id              SERIAL PRIMARY KEY,
    role            TEXT NOT NULL,
    permission_code TEXT NOT NULL REFERENCES permission (code) ON DELETE CASCADE,
    UNIQUE (role, permission_code)
);

-- ==================== SSO / OIDC ====================
-- Lien compte externe ↔ utilisateur KPay (email match strict après userinfo)
CREATE TABLE IF NOT EXISTS user_sso (
    id             SERIAL PRIMARY KEY,
    user_id        INT NOT NULL REFERENCES "user" (id) ON DELETE CASCADE,
    provider       TEXT NOT NULL,
    external_sub   TEXT NOT NULL,
    email          TEXT NOT NULL,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (provider, external_sub)
);

-- États PKCE OIDC (state → code_verifier) pendant le flow Authorization Code
CREATE TABLE IF NOT EXISTS sso_state (
    state         TEXT PRIMARY KEY,
    code_verifier TEXT NOT NULL,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at    TIMESTAMP NOT NULL
);

-- ==================== MFA TOTP ====================
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS mfa_secret TEXT DEFAULT '';
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS mfa_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS mfa_backup_codes TEXT DEFAULT '';

-- ==================== SEED PERMISSIONS ====================
INSERT INTO permission (code, label, module_name) VALUES
 ('dashboard.view',   'Consulter le tableau de bord', 'general'),
 ('employee.manage',  'Gérer les employés', 'hr'),
 ('contract.manage',  'Gérer les contrats', 'hr'),
 ('payroll.calculate','Calculer la paie', 'payroll'),
 ('payroll.run',      'Générer & sauvegarder la paie mensuelle', 'payroll'),
 ('payroll.book',     'Consulter le livre de paie', 'payroll'),
 ('payslip.read.all', 'Consulter tous les bulletins', 'payroll'),
 ('payslip.read.self','Consulter ses bulletins', 'payroll'),
 ('payslip.manage',   'Valider / rejeter / payer les bulletins', 'payroll'),
 ('leave.request',    'Poser des congés', 'leave'),
 ('leave.approve.mgr','Valider les congés de son équipe (N+1)', 'leave'),
 ('leave.approve.rh', 'Valider les congés niveau RH', 'leave'),
 ('leave.read.all',   'Consulter toutes les absences', 'leave'),
 ('tax_rule.manage',  'Gérer les règles sociales', 'tax'),
 ('user.manage',      'Gérer les comptes utilisateurs', 'admin'),
 ('role.manage',      'Administrer les rôles & permissions', 'admin'),
 ('org.settings',     'Configurer les paramètres de l''organisation', 'admin'),
 ('audit.read',       'Consulter le journal d''audit', 'admin'),
 ('profile.review',   'Valider les demandes de modification de profil', 'hr')
ON CONFLICT (code) DO NOTHING;

-- Mappings par défaut (le rôle admin possède toutes les permissions de façon implicite côté serveur)
INSERT INTO role_permission (role, permission_code)
SELECT 'payroll_officer', code FROM permission WHERE module_name IN ('hr', 'payroll', 'leave')
ON CONFLICT (role, permission_code) DO NOTHING;
INSERT INTO role_permission (role, permission_code)
SELECT 'accountant', code FROM permission WHERE module_name IN ('payroll', 'tax')
ON CONFLICT (role, permission_code) DO NOTHING;
INSERT INTO role_permission (role, permission_code)
SELECT 'manager', code FROM permission WHERE code IN ('dashboard.view', 'payslip.read.self', 'leave.request', 'leave.approve.mgr', 'leave.read.all')
ON CONFLICT (role, permission_code) DO NOTHING;
INSERT INTO role_permission (role, permission_code)
SELECT 'employee', code FROM permission WHERE code IN ('dashboard.view', 'payslip.read.self', 'leave.request')
ON CONFLICT (role, permission_code) DO NOTHING;