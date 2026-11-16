import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { Employee, Contract, Payslip, LeaveRequest, LeaveBalance, PayRun, ProfileChangeRequest, TaxComponent, TaxBracket, TaxImpactRequest, TaxImpactResponse, OrgLeaveSettings, OrgLeaveSettingsInput, MfaStatus, MfaEnrollResponse, SsoConfig, UserSsoLink, Permission, RoleWithPermissions, PageResponse, User, UserCreateInput, UserUpdateInput, Job, JobRunResponse, DisaPreview, DisaSealed, PayslipLine, Adjustment, Timesheet, PayrollBook, MissingPayslip, DeclarationExport, ChainCheck } from '../models/kpay.models';

@Injectable({
    providedIn: 'root'
})
export class ApiService {
    private baseUrl = '/api/v1';

    constructor(private http: HttpClient) { }

    // --- Employees ---
    getEmployees(): Observable<Employee[]> {
        return this.http.get<PageResponse<Employee>>(`${this.baseUrl}/employees`).pipe(map((r) => r.data));
    }

    getEmployeeById(id: number): Observable<Employee> {
        return this.http.get<Employee>(`${this.baseUrl}/employees/${id}`);
    }

    createEmployee(employee: Partial<Employee>): Observable<Employee> {
        return this.http.post<Employee>(`${this.baseUrl}/employees`, employee);
    }

    updateEmployee(id: number, employee: Partial<Employee>): Observable<{ success: boolean; message: string }> {
        return this.http.put<{ success: boolean; message: string }>(`${this.baseUrl}/employees/${id}`, employee);
    }

    // --- Contracts ---
    getActiveContract(employeeId: number): Observable<Contract> {
        return this.http.get<Contract>(`${this.baseUrl}/contracts/${employeeId}`);
    }

    // --- Payroll / Payslips ---
    getPayslips(month?: number, year?: number): Observable<Payslip[]> {
        let params = new HttpParams();
        if (month) params = params.set('month', month);
        if (year) params = params.set('year', year);
        return this.http.get<Payslip[]>(`${this.baseUrl}/payslips`, { params });
    }

    getPayslip(id: number): Observable<Payslip> {
        return this.http.get<Payslip>(`${this.baseUrl}/payslips/${id}`);
    }

    calculatePayslip(employeeId: number, month: number, year: number): Observable<PayRun> {
        return this.http.post<PayRun>(`${this.baseUrl}/payroll/calculate`, { employee_id: employeeId, month, year });
    }

    runPayroll(month: number, year: number): Observable<JobRunResponse> {
        return this.http.post<JobRunResponse>(`${this.baseUrl}/payroll/run`, { month, year });
    }

    // --- Jobs asynchrones (Pilier 4 : file de traitement + SSE) ---
    getJob(jobId: number): Observable<Job> {
        return this.http.get<Job>(`${this.baseUrl}/jobs/${jobId}`);
    }

    getJobs(page: number = 1, limit: number = 25): Observable<PageResponse<Job>> {
        let params = new HttpParams().set('page', page).set('limit', limit);
        return this.http.get<PageResponse<Job>>(`${this.baseUrl}/jobs`, { params });
    }

    retryJob(jobId: number): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/jobs/${jobId}/retry`, {});
    }

    purgeJobs(days: number = 30): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/jobs/purge?days=${days}`, {});
    }

    // URL du flux SSE temps réel de progression d'un job. EventSource ne gère pas
    // les headers Authorization : le token JWT est passé en query param.
    jobEventsUrl(jobId: number): string {
        const token = localStorage.getItem('kpay_jwt_token') || '';
        return `${this.baseUrl}/events/jobs/${jobId}?token=${encodeURIComponent(token)}`;
    }

    recalculatePayslip(payslipId: number): Observable<Payslip> {
        return this.http.post<Payslip>(`${this.baseUrl}/payslips/${payslipId}/recalculate`, {});
    }

    getPayslipLines(payslipId: number): Observable<PayslipLine[]> {
        return this.http.get<PayslipLine[]>(`${this.baseUrl}/payslips/${payslipId}/lines`);
    }

    submitPayslip(payslipId: number): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/payslips/${payslipId}/submit`, {});
    }

    approvePayslip(payslipId: number): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/payslips/${payslipId}/approve`, {});
    }

    rejectPayslip(payslipId: number): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/payslips/${payslipId}/reject`, {});
    }

    payPayslip(payslipId: number): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/payslips/${payslipId}/pay`, {});
    }

    getEmployeePayslips(employeeId: number): Observable<Payslip[]> {
        return this.http.get<Payslip[]>(`${this.baseUrl}/employees/${employeeId}/payslips`);
    }

    // --- ESS : Mes bulletins (self-service) ---
    getMyPayslips(month?: number, year?: number): Observable<Payslip[]> {
        let params = new HttpParams();
        if (month) params = params.set('month', month);
        if (year) params = params.set('year', year);
        return this.http.get<Payslip[]>(`${this.baseUrl}/me/payslips`, { params });
    }

    getMyPayslipPdf(payslipId: number): Observable<Blob> {
        return this.http.get(`${this.baseUrl}/me/payslips/${payslipId}/pdf`, { responseType: 'blob' });
    }

    // --- Leaves ---
    getLeaveRequests(): Observable<LeaveRequest[]> {
        return this.http.get<LeaveRequest[]>(`${this.baseUrl}/leaves`);
    }

    createLeaveRequest(request: Partial<LeaveRequest>): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/leaves`, request);
    }

    setLeaveStatus(leaveId: number, status: 'approuve' | 'refuse'): Observable<{ success: boolean; message: string }> {
        return this.http.put<{ success: boolean; message: string }>(`${this.baseUrl}/leaves/${leaveId}/status`, { status });
    }

    // --- ESS : Mes congés & workflow 2 niveaux ---
    getMyLeaveRequests(): Observable<LeaveRequest[]> {
        return this.http.get<LeaveRequest[]>(`${this.baseUrl}/me/leaves`);
    }

    createMyLeaveRequest(request: Partial<LeaveRequest>): Observable<LeaveRequest> {
        return this.http.post<LeaveRequest>(`${this.baseUrl}/me/leaves`, request);
    }

    getMyLeaveBalance(year?: number): Observable<LeaveBalance[]> {
        let params = new HttpParams();
        if (year) params = params.set('year', year);
        return this.http.get<LeaveBalance[]>(`${this.baseUrl}/me/leave-balance`, { params });
    }

    getTeamLeaveRequests(): Observable<LeaveRequest[]> {
        return this.http.get<LeaveRequest[]>(`${this.baseUrl}/leaves?my_team=1`);
    }

    mgrApproveLeave(leaveId: number): Observable<LeaveRequest> {
        return this.http.post<LeaveRequest>(`${this.baseUrl}/leaves/${leaveId}/mgr-approve`, {});
    }

    mgrRejectLeave(leaveId: number, reason: string): Observable<LeaveRequest> {
        return this.http.post<LeaveRequest>(`${this.baseUrl}/leaves/${leaveId}/mgr-reject`, { reason });
    }

    rhApproveLeave(leaveId: number): Observable<LeaveRequest> {
        return this.http.post<LeaveRequest>(`${this.baseUrl}/leaves/${leaveId}/rh-approve`, {});
    }

    rhRejectLeave(leaveId: number, reason: string): Observable<LeaveRequest> {
        return this.http.post<LeaveRequest>(`${this.baseUrl}/leaves/${leaveId}/rh-reject`, { reason });
    }

    uploadLeaveJustificatif(leaveId: number, base64Content: string, filename: string): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/leaves/${leaveId}/justificatif`, { content: base64Content, filename });
    }

    downloadLeaveJustificatif(leaveId: number): Observable<Blob> {
        return this.http.get(`${this.baseUrl}/leaves/${leaveId}/justificatif`, { responseType: 'blob' });
    }

    // --- ESS : Profil & validation RH ---
    getMe(): Observable<Employee> {
        return this.http.get<Employee>(`${this.baseUrl}/me`);
    }

    requestProfileChange(field: string, value: string): Observable<ProfileChangeRequest> {
        return this.http.post<ProfileChangeRequest>(`${this.baseUrl}/me/profile`, { field, value });
    }

    getMyProfileRequests(): Observable<ProfileChangeRequest[]> {
        return this.http.get<ProfileChangeRequest[]>(`${this.baseUrl}/me/profile-requests`);
    }

    getProfileChanges(status?: string): Observable<ProfileChangeRequest[]> {
        let params = new HttpParams();
        if (status) params = params.set('status', status);
        return this.http.get<ProfileChangeRequest[]>(`${this.baseUrl}/profile-changes`, { params });
    }

    approveProfileChange(id: number): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/profile-changes/${id}/approve`, {});
    }

    rejectProfileChange(id: number, reason: string): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/profile-changes/${id}/reject`, { reason });
    }

    // --- Règles sociales (Pilier 2.2 — moteur de règles fiscales dynamiques) ---
    getTaxComponents(): Observable<TaxComponent[]> {
        return this.http.get<TaxComponent[]>(`${this.baseUrl}/admin/tax-components`);
    }

    createTaxComponent(component: Partial<TaxComponent>): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/tax-components`, component);
    }

    updateTaxComponent(id: number, component: Partial<TaxComponent>): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.put<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/tax-components/${id}`, component);
    }

    getTaxBrackets(): Observable<TaxBracket[]> {
        return this.http.get<TaxBracket[]>(`${this.baseUrl}/admin/tax-brackets`);
    }

    createTaxBracket(bracket: Partial<TaxBracket>): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/tax-brackets`, bracket);
    }

    updateTaxBracket(id: number, bracket: Partial<TaxBracket>): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.put<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/tax-brackets/${id}`, bracket);
    }

    computeTaxImpact(request: TaxImpactRequest): Observable<TaxImpactResponse> {
        return this.http.post<TaxImpactResponse>(`${this.baseUrl}/admin/tax-impact`, request);
    }

    // --- Paramètres congés par organisation (Pilier 1.2) ---
    getOrgLeaveSettings(): Observable<OrgLeaveSettings> {
        return this.http.get<OrgLeaveSettings>(`${this.baseUrl}/admin/org-settings`);
    }

    updateOrgLeaveSettings(input: OrgLeaveSettingsInput): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.put<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/org-settings`, input);
    }

    // --- MFA TOTP + SSO (Pilier 3) ---
    getMfaStatus(): Observable<MfaStatus> {
        return this.http.get<MfaStatus>(`${this.baseUrl}/mfa/status`);
    }

    enrollMfa(): Observable<MfaEnrollResponse> {
        return this.http.post<MfaEnrollResponse>(`${this.baseUrl}/mfa/enroll`, {});
    }

    verifyMfa(code: string): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/mfa/verify`, { code });
    }

    disableMfa(password: string): Observable<{ success: boolean; message: string }> {
        return this.http.post<{ success: boolean; message: string }>(`${this.baseUrl}/mfa/disable`, { password });
    }

    getSsoConfig(): Observable<SsoConfig> {
        return this.http.get<SsoConfig>(`${this.baseUrl}/auth/sso/config`);
    }

    getMySsoLinks(): Observable<UserSsoLink[]> {
        return this.http.get<UserSsoLink[]>(`${this.baseUrl}/me/sso`);
    }

    deleteMySsoLink(id: number): Observable<{ success: boolean; message: string }> {
        return this.http.delete<{ success: boolean; message: string }>(`${this.baseUrl}/me/sso/${id}`);
    }

    // --- RBAC (Pilier 3) ---
    getPermissions(): Observable<Permission[]> {
        return this.http.get<Permission[]>(`${this.baseUrl}/admin/permissions`);
    }

    getRoles(): Observable<RoleWithPermissions[]> {
        return this.http.get<RoleWithPermissions[]>(`${this.baseUrl}/admin/roles`);
    }

    updateRolePermissions(role: string, permissions: string[]): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.put<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/roles/${role}/permissions`, { permissions });
    }

    getUsers(): Observable<PageResponse<User>> {
        return this.http.get<PageResponse<User>>(`${this.baseUrl}/admin/users`);
    }

    createUser(input: UserCreateInput): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/users`, input);
    }

    updateUser(id: number, input: UserUpdateInput): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.put<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/admin/users/${id}`, input);
    }

    // --- Déclarations sociales (Pilier 5.1) ---
    getDisaPreview(year: number): Observable<DisaPreview> {
        return this.http.get<DisaPreview>(`${this.baseUrl}/exports/disa/preview`, { params: new HttpParams().set('year', year) });
    }

    exportDisa(year: number): Observable<DisaSealed> {
        return this.http.post<DisaSealed>(`${this.baseUrl}/exports/disa`, { year });
    }

    getDeclarations(kind?: string): Observable<DeclarationExport[]> {
        let params = new HttpParams();
        if (kind) params = params.set('kind', kind);
        return this.http.get<DeclarationExport[]>(`${this.baseUrl}/exports/declarations`, { params });
    }

    verifyDeclarations(): Observable<ChainCheck> {
        return this.http.get<ChainCheck>(`${this.baseUrl}/exports/declarations/verify`);
    }

    downloadDeclaration(id: number): Observable<Blob> {
        return this.http.get(`${this.baseUrl}/exports/declarations/${id}/file`, { responseType: 'blob' });
    }

    // --- Dossier salarié : contrats, primes/retenues, heures ---
    getEmployeeContracts(employeeId: number): Observable<Contract[]> {
        return this.http.get<Contract[]>(`${this.baseUrl}/employees/${employeeId}/contracts`);
    }

    createContract(contract: { employee_id: number; base_salary: number; hourly_rate: number; start_date: string; currency: string }): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/contracts`, contract);
    }

    endContract(contractId: number, endDate: string): Observable<{ success: boolean; message: string }> {
        return this.http.put<{ success: boolean; message: string }>(`${this.baseUrl}/contracts/${contractId}/end`, { end_date: endDate });
    }

    getAdjustments(employeeId: number): Observable<Adjustment[]> {
        return this.http.get<Adjustment[]>(`${this.baseUrl}/employees/${employeeId}/adjustments`);
    }

    createAdjustment(adj: { employee_id: number; month: number; year: number; amount: number; description: string }): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/adjustments`, adj);
    }

    deleteAdjustment(id: number): Observable<{ success: boolean; message: string }> {
        return this.http.delete<{ success: boolean; message: string }>(`${this.baseUrl}/adjustments/${id}`);
    }

    getTimesheets(employeeId: number): Observable<Timesheet[]> {
        return this.http.get<Timesheet[]>(`${this.baseUrl}/employees/${employeeId}/timesheets`);
    }

    saveTimesheet(ts: { employee_id: number; month: number; year: number; hours_worked: number; overtime_h: number }): Observable<{ success: boolean; data: string; message: string }> {
        return this.http.post<{ success: boolean; data: string; message: string }>(`${this.baseUrl}/timesheets`, ts);
    }

    deleteTimesheet(id: number): Observable<{ success: boolean; message: string }> {
        return this.http.delete<{ success: boolean; message: string }>(`${this.baseUrl}/timesheets/${id}`);
    }

    // --- Livre de paie, virements, bulletins manquants ---
    getPayrollBook(month: number, year: number): Observable<PayrollBook> {
        return this.http.get<PayrollBook>(`${this.baseUrl}/payroll/book`, { params: new HttpParams().set('month', month).set('year', year) });
    }

    downloadPayrollBook(month: number, year: number, format: 'csv' | 'pdf'): Observable<Blob> {
        return this.http.get(`${this.baseUrl}/payroll/book/${format}`, { params: new HttpParams().set('month', month).set('year', year), responseType: 'blob' });
    }

    downloadSepa(month: number, year: number): Observable<Blob> {
        return this.http.get(`${this.baseUrl}/exports/sepa`, { params: new HttpParams().set('month', month).set('year', year), responseType: 'blob' });
    }

    getMissingPayslips(month: number, year: number): Observable<MissingPayslip[]> {
        return this.http.get<MissingPayslip[]>(`${this.baseUrl}/payroll/missing`, { params: new HttpParams().set('month', month).set('year', year) });
    }

    generateEmployeePayslip(employeeId: number, month: number, year: number): Observable<Payslip> {
        return this.http.post<Payslip>(`${this.baseUrl}/payroll/run-employee`, { employee_id: employeeId, month, year });
    }
}
