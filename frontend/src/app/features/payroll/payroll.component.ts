import { Component, inject, OnInit, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { Payslip } from '../../core/models/kpay.models';

@Component({
    selector: 'app-payroll',
    standalone: true,
    imports: [FormsModule, DecimalPipe],
    template: `
    <div class="space-y-6">
      <div class="page-head">
        <div>
          <h1 class="page-title">Gestion de la Paie</h1>
          <p class="page-subtitle">Générez la paie mensuelle et suivez le workflow des bulletins.</p>
        </div>
        <button
          (click)="runPayroll()"
          [disabled]="isRunning()"
          class="btn btn-primary disabled:opacity-50"
        >
          @if (isRunning()) {
            <span class="inline-block animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
            Génération...
          } @else {
            Lancer la Paie ({{ selectedMonth }}/{{ selectedYear }})
          }
        </button>
      </div>

      <!-- Filtres période -->
      <div class="flex items-center gap-2 flex-wrap">
        <select [(ngModel)]="selectedMonth" name="month" class="select w-auto">
          @for (m of months; track m.value) {
            <option [value]="m.value">{{ m.label }}</option>
          }
        </select>
        <select [(ngModel)]="selectedYear" name="year" class="select w-auto">
          @for (y of years; track y) {
            <option [value]="y">{{ y }}</option>
          }
        </select>
        <button (click)="loadPayslips()" class="btn btn-secondary">Filtrer</button>
      </div>

      <!-- Message erreur -->
      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }

      <!-- Message succès -->
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      <!-- Bulletins -->
      <div class="card overflow-hidden">
        <table class="data-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Employé</th>
              <th>Période</th>
              <th class="text-right">Brut</th>
              <th class="text-right">Net</th>
              <th>Statut</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (p of payslips(); track p.id) {
              <tr>
                <td class="px-4 py-3.5 font-mono text-xs text-slate-400">#{{ p.id }}</td>
                <td class="px-4 py-3.5 font-medium text-slate-900">{{ employeeName(p.employee_id) }}</td>
                <td class="px-4 py-3.5 text-slate-500">{{ formatPeriod(p.paid_at || p.period_start) }}</td>
                <td class="px-4 py-3.5 num">{{ p.gross_amount | number }} F</td>
                <td class="px-4 py-3.5 num font-semibold text-slate-900">{{ p.net_amount | number }} F</td>
                <td class="px-4 py-3.5">
                  <span [class]="statusClass(p.status)">
                    {{ statusLabel(p.status) }}
                  </span>
                </td>
                <td class="px-4 py-3.5">
                  <div class="flex gap-1.5 justify-end">
                    @if (p.status === 'brouillon' || p.status === 'rejete') {
                      <button (click)="submit(p.id)" class="btn btn-sm btn-secondary">Soumettre</button>
                    }
                    @if (p.status === 'soumis') {
                      <button (click)="approve(p.id)" class="btn btn-sm btn-secondary">Approuver</button>
                      <button (click)="reject(p.id)" class="btn btn-sm btn-danger">Rejeter</button>
                    }
                    @if (p.status === 'approuve') {
                      <button (click)="pay(p.id)" class="btn btn-sm btn-success">Payer</button>
                    }
                  </div>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7" class="px-4 py-8 text-center text-slate-400">
                  Aucun bulletin pour cette période. Lancez la génération de paie.
                </td>
              </tr>
            }
          </tbody>
          @if (payslips().length > 0) {
            <tfoot>
              <tr>
                <td colspan="3">Total ({{ payslips().length }} bulletin(s))</td>
                <td class="num">{{ totalGross() | number }} F</td>
                <td class="num">{{ totalNet() | number }} F</td>
                <td></td>
                <td></td>
              </tr>
            </tfoot>
          }
        </table>
      </div>
    </div>
  `
})
export class PayrollComponent implements OnInit {
    private apiService = inject(ApiService);

    payslips = signal<Payslip[]>([]);
    employees = signal<Map<number, string>>(new Map());
    isRunning = signal(false);
    errorMessage = signal('');
    successMessage = signal('');

    selectedMonth: number = 0;
    selectedYear: number = 0;

    months = Array.from({ length: 12 }, (_, i) => ({ value: i + 1, label: new Date(2026, i, 1).toLocaleDateString('fr-FR', { month: 'long' }) }));

    ngOnInit(): void {
        const now = new Date();
        this.selectedMonth = now.getMonth() + 1;
        this.selectedYear = now.getFullYear();
        this.loadEmployees();
        this.loadPayslips();
    }

    get years(): number[] {
        const current = new Date().getFullYear();
        return [current - 1, current, current + 1];
    }

    loadEmployees(): void {
        this.apiService.getEmployees().subscribe({
            next: (list) => {
                const map = new Map<number, string>();
                for (const e of list) map.set(e.id, `${e.last_name} ${e.first_name}`);
                this.employees.set(map);
            },
            error: () => this.employees.set(new Map())
        });
    }

    loadPayslips(): void {
        this.errorMessage.set('');
        this.successMessage.set('');
        this.apiService.getPayslips(this.selectedMonth, this.selectedYear).subscribe({
            next: (data) => this.payslips.set(data),
            error: (err) => {
                this.payslips.set([]);
                this.errorMessage.set(this.extractError(err) || 'Impossible de charger les bulletins.');
            }
        });
    }

    runPayroll(): void {
        this.isRunning.set(true);
        this.errorMessage.set('');
        this.successMessage.set('');
        this.apiService.runPayroll(this.selectedMonth, this.selectedYear).subscribe({
            next: (res) => {
                this.isRunning.set(false);
                this.successMessage.set(`${res.count} bulletin(s) généré(s) pour ${this.selectedMonth}/${this.selectedYear}.`);
                this.loadPayslips();
            },
            error: (err) => {
                this.isRunning.set(false);
                this.errorMessage.set(this.extractError(err) || 'Erreur lors de la génération de la paie.');
            }
        });
    }

    submit(id: number): void {
        this.workflowAction(() => this.apiService.submitPayslip(id), 'Bulletin soumis pour approbation.');
    }

    approve(id: number): void {
        this.workflowAction(() => this.apiService.approvePayslip(id), 'Bulletin approuvé.');
    }

    reject(id: number): void {
        this.workflowAction(() => this.apiService.rejectPayslip(id), 'Bulletin rejeté.');
    }

    pay(id: number): void {
        this.workflowAction(() => this.apiService.payPayslip(id), 'Bulletin marqué comme payé.');
    }

    private workflowAction(action: () => any, successMsg: string): void {
        this.errorMessage.set('');
        this.successMessage.set('');
        action().subscribe({
            next: () => {
                this.successMessage.set(successMsg);
                this.loadPayslips();
            },
            error: (err: any) => this.errorMessage.set(this.extractError(err) || 'Action impossible sur ce bulletin.')
        });
    }

    employeeName(id: number): string {
        return this.employees().get(id) || `Employé #${id}`;
    }

    formatPeriod(dateStr: string): string {
        if (!dateStr) return '—';
        const d = new Date(dateStr);
        return d.toLocaleDateString('fr-FR');
    }

    statusLabel(status: string): string {
        const labels: Record<string, string> = {
            brouillon: 'Brouillon',
            soumis: 'Soumis',
            approuve: 'Approuvé',
            rejete: 'Rejeté',
            paye: 'Payé'
        };
        return labels[status] || status;
    }

    statusClass(status: string): string {
        const classes: Record<string, string> = {
            brouillon: 'badge badge-slate',
            soumis: 'badge badge-amber',
            approuve: 'badge badge-blue',
            rejete: 'badge badge-rose',
            paye: 'badge badge-emerald'
        };
        return classes[status] || 'badge badge-slate';
    }

    totalGross(): number {
        return this.payslips().reduce((acc, p) => acc + p.gross_amount, 0);
    }

    totalNet(): number {
        return this.payslips().reduce((acc, p) => acc + p.net_amount, 0);
    }

    private extractError(err: any): string {
        if (err?.error) {
            if (typeof err.error === 'string') return err.error;
            if (err.error.error) return err.error.error;
            if (err.error.message) return err.error.message;
        }
        return err?.message || '';
    }
}