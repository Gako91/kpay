import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Employee, Contract, Payslip, LeaveRequest, PayRun } from '../models/kpay.models';

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
}