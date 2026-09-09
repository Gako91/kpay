export interface User {
    id: number;
    organization_id: number;
    username: string;
    role: 'admin' | 'payroll_officer' | 'accountant' | 'manager' | 'employee';
    email: string;
    is_active: boolean;
    created_at?: string;
}

export interface Employee {
    id: number;
    organization_id: number;
    first_name: string;
    last_name: string;
    email: string;
    iban?: string;
    bic?: string;
    phone?: string;
    address?: string;
    tax_parts: number;
    is_active: boolean;
    user_id?: number;
    manager_id?: number;
}

export interface ProfileChangeRequest {
    id: number;
    organization_id: number;
    employee_id: number;
    field_name: 'iban' | 'bic' | 'phone' | 'address' | 'tax_parts';
    old_value: string;
    new_value: string;
    status: 'en_attente' | 'approuve' | 'refuse';
    rejection_reason?: string;
    requested_at: string;
    reviewed_by?: string;
    reviewed_at?: string;
}

export interface Contract {
    id: number;
    organization_id: number;
    employee_id: number;
    base_salary: number;
    hourly_rate: number;
    start_date: string;
    end_date?: string;
    contract_type?: string;
}

export interface Payslip {
    id: number;
    organization_id: number;
    employee_id: number;
    period_start: string;
    period_end: string;
    gross_amount: number;
    total_taxes: number;
    net_amount: number;
    is_paid: boolean;
    paid_at?: string;
    pdf_path?: string;
    status: 'brouillon' | 'soumis' | 'approuve' | 'rejete' | 'paye';
    approved_by?: string;
    approved_at?: string;
}

export interface LeaveRequest {
    id: number;
    employee_id: number;
    leave_type: 'conge_paye' | 'rtt' | 'maladie' | 'sans_solde';
    start_date: string;
    end_date: string;
    days_count: number;
    reason: string;
    status: 'en_attente' | 'valide_mgr' | 'approuve' | 'refuse';
    approved_by_mgr?: string;
    approved_at_mgr?: string;
    approved_by?: string;
    approved_at?: string;
    rejection_reason?: string;
    justificatif_path?: string;
    created_at?: string;
}

export interface LeaveBalance {
    id: number;
    organization_id: number;
    employee_id: number;
    year: number;
    leave_type: 'conge_paye' | 'rtt' | 'maladie' | 'sans_solde';
    accrued_days: number;
    used_days: number;
}

export interface PayRun {
    employee_id: number;
    gross_pay: number;
    tax_amount: number;
    net_pay: number;
    date: string;
}

export interface AuthResponse {
    success: boolean;
    token: string;
    sub: string;
    role: string;
    org: number;
    expires: string;
    challenge?: string;   // 'totp' si le MFA est requis en 2e étape
    mfa_token?: string;   // token court de la 2e étape
}

export interface LoginRequest {
    username: string;
    password: string;
}

// --- Sécurité (Pilier 3 — MFA TOTP + SSO OIDC) ---
export interface MfaLoginRequest {
    mfa_token: string;
    code: string;
}

export interface MfaEnrollResponse {
    secret: string;
    otpauth_uri: string;
    backup_codes: string[];
}

export interface MfaStatus {
    enabled: boolean;
    backup_codes_count: number;
}

export interface SsoConfig {
    enabled: boolean;
    issuer: string;
    client_id: string;
    redirect_uri: string;
    scopes: string;
}

export interface UserSsoLink {
    id: number;
    user_id: number;
    provider: string;
    external_sub: string;
    email: string;
}

// --- RBAC (Pilier 3) ---
export interface Permission {
    code: string;
    label: string;
    module_name: string;
}

export interface RoleWithPermissions {
    role: string;
    permissions: string[];
    builtin: boolean;
}

// --- Règles sociales (Pilier 2.2 — moteur de règles fiscales dynamiques) ---
export interface TaxComponent {
    id?: number;
    organization_id?: number;
    code: string;
    name: string;
    rate: number; // décimal (ex: 0.063 = 6.3%)
    basis_type: 'brut' | 'plafonne' | 'forfait' | 'brut80';
    cap?: number; // plafond d'assiette FCFA (0 = non plafonné)
    fixed_amount?: number; // montant forfaitaire FCFA
    share: 'salarial' | 'patronal';
    effective_from?: string; // 'YYYY-MM-DD'
    is_active?: boolean;
    country?: string;
}

export interface TaxBracket {
    id?: number;
    organization_id?: number;
    component_code: 'CN' | 'IGR';
    lower_bound: number;
    upper_bound: number; // -1 = non borné
    rate: number; // taux marginal décimal
    flat: number; // constante : amount = round(base*rate - flat)
    effective_from?: string;
    is_active?: boolean;
}

export interface TaxLine {
    name: string;
    amount: number;
}

export interface TaxImpactRequest {
    gross: number;
    tax_parts: number;
    period?: string;
    components?: TaxComponent[];
    brackets?: TaxBracket[];
}

export interface TaxImpactResult {
    net: number;
    taxes: number;
    details: TaxLine[];
}

export interface TaxImpactResponse {
    current: TaxImpactResult;
    proposed: TaxImpactResult;
    delta_net: number;
}

// --- Paramètres d'organisation (Pilier 1.2 — règles de carence & délai de déclaration) ---
export interface OrgLeaveSettings {
    id: number;
    name: string;
    leave_carence_days: number;
    leave_declaration_deadline_days: number;
}

export interface OrgLeaveSettingsInput {
    carence_days: number;
    deadline_days: number;
}

// --- Gestion des comptes (Pilier 3 — user.manage) ---
export interface UserCreateInput {
    username: string;
    password: string;
    email: string;
    role: string;
}

export interface UserUpdateInput {
    role: string;
    is_active: boolean;
}

export interface PageResponse<T> {
    data: T[];
    page: number;
    page_size: number;
    total: number;
    total_pages: number;
}
