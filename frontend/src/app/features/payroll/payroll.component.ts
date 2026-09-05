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
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Gestion de la Paie</h1>
          <p class="text-slate-500 text-sm">Générez la paie mensuelle et suivez le workflow des bulletins.</p>
        </div>
        <button
          (click)="runPayroll()"
          [disabled]="isRunning()"
          class="bg-emerald-600 hover:bg-emerald-700 text-white font-medium px-4 py-2.5 rounded-lg text-sm transition shadow flex items-center gap-2 disabled:opacity-50"
        >
          @if (isRunning()) {
            <span class="inline-block animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
            Génération...
          } @else {
            ⚡ Lancer la Paie ({{ selectedMonth }}/{{ selectedYear }})
          }
        </button>
      </div>

      <!-- Filtres période -->
      <div class="flex items-center gap-3">
        <div class="flex items-center gap-2">
          <select [(ngModel)]="selectedMonth" name="month" class="px-3 py-2 rounded-lg border border-slate-300 text-sm bg-white">
            @for (m of months; track m.value) {
              <option [value]="m.value">{{ m.label }}</option>
            }
          </select>
          <select [(ngModel)]="selectedYear" name="year" class="px-3 py-2 rounded-lg border border-slate-300 text-sm bg-white">
            @for (y of years; track y) {
              <option [value]="y">{{ y }}</option>
            }
          </select>
          <button (click)="loadPayslips()" class="px-4 py-2 text-sm font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg">Filtrer</button>
        </div>
      </div>

      <!-- Message erreur -->
      @if (errorMessage()) {
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">{{ errorMessage() }}</div>
      }

      <!-- Message succès -->
      @if (successMessage()) {
        <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg text-sm">{{ successMessage() }}</div>
      }

      <!-- Bulletins -->
      <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <table class="w-full text-left text-sm text-slate-600">
          <thead class="bg-slate-50 text-slate-700 uppercase font-semibold text-xs border-b border-slate-200">
            <tr>
              <th class="px-6 py-3.5">ID</th>
              <th class="px-6 py-3.5">Employé</th>
              <th class="px-6 py-3.5">Période</th>
              <th class="px-6 py-3.5 text-right">Brut</th>
              <th class="px-6 py-3.5 text-right">Net</th>
              <th class="px-6 py-3.5">Statut</th>
              <th class="px-6 py-3.5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y border-slate-100">
            @for (p of payslips(); track p.id) {
              <tr class="hover:bg-slate-50 transition">
                <td class="px-6 py-4 font-mono text-xs text-slate-400">#{{ p.id }}</td>
                <td class="px-6 py-4 font-medium text-slate-900">{{ employeeName(p.employee_id) }}</td>
                <td class="px-6 py-4 text-slate-500">{{ formatPeriod(p.paid_at || p.period_start) }}</td>
                <td class="px-6 py-4 text-right">{{ p.gross_amount | number }} F</td>
                <td class="px-6 py-4 text-right font-semibold text-slate-900">{{ p.net_amount | number }} F</td>
                <td class="px-6 py-4">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium" [class]="statusClass(p.status)">
                    {{ statusLabel(p.status) }}
                  </span>
                </td>
                <td class="px-6 py-4">
                  <div class="flex gap-2 justify-end">
                    @if (p.status === 'brouillon' || p.status === 'rejete') {
                      <button (click)="submit(p.id)" class="px-3 py-1.5 text-xs font-medium bg-sky-600 hover:bg-sky-700 text-white rounded-lg">Soumettre</button>
                    }
                    @if (p.status === 'soumis') {
                      <button (click)="approve(p.id)" class="px-3 py-1.5 text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg">Approuver</button>
                      <button (click)="reject(p.id)" class="px-3 py-1.5 text-xs font-medium bg-amber-600 hover:bg-amber-700 text-white rounded-lg">Rejeter</button>
                    }
                    @if (p.status === 'approuve') {
                      <button (click)="pay(p.id)" class="px-3 py-1.5 text-xs font-medium bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg">Payer</button>
                    }
                  </div>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="7" class="px-6 py-8 text-center text-slate-400">
                  Aucun bulletin pour cette période. Lancez la génération de paie.
                </td>
              </tr>
            }
          </tbody>
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
            brouillon: 'bg-slate-100 text-slate-800',
            soumis: 'bg-sky-100 text-sky-800',
            approuve: 'bg-blue-100 text-blue-800',
            rejete: 'bg-amber-100 text-amber-800',
            paye: 'bg-emerald-100 text-emerald-800'
        };
        return classes[status] || 'bg-slate-100 text-slate-800';
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