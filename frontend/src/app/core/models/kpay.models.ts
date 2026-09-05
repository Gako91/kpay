export interface User {
    id: number;
    organization_id: number;
    username: string;
    role: 'admin' | 'payroll_officer' | 'accountant' | 'employee';
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
    tax_parts: number;
    is_active: boolean;
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
    status: 'en_attente' | 'approuve' | 'refuse';
    approved_by?: string;
    created_at?: string;
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
    expires: string;
}

export interface LoginRequest {
    username: string;
    password: string;
}
