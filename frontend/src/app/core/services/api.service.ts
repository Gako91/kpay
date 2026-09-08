import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Employee, Contract, Payslip, LeaveRequest, LeaveBalance, PayRun, ProfileChangeRequest, TaxComponent, TaxBracket, TaxImpactRequest, TaxImpactResponse } from '../models/kpay.models';

@Injectable({
    providedIn: 'root'
})
export class ApiService {
    private baseUrl = '/api/v1';

    constructor(private http: HttpClient) { }

    // --- Employees ---
    getEmployees(): Observable<Employee[]> {
        return this.http.get<Employee[]>(`${this.baseUrl}/employees`);
    }

    getEmployeeById(id: number): Observable<Employee> {
        return this.http.get<Employee>(`${this.baseUrl}/employees/${id}`);
    }

    createEmployee(employee: Partial<Employee>): Observable<Employee> {
        return this.http.post<Employee>(`${this.baseUrl}/employees`, employee);
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

    runPayroll(month: number, year: number): Observable<{ success: boolean; count: number; payslips: Payslip[] }> {
        return this.http.post<{ success: boolean; count: number; payslips: Payslip[] }>(`${this.baseUrl}/payroll/run`, { month, year });
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
}