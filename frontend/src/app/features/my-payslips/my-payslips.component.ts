import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { Payslip } from '../../core/models/kpay.models';

@Component({
    selector: 'app-my-payslips',
    standalone: true,
    imports: [FormsModule, CommonModule],
    template: `
    <div class="space-y-6">
      <!-- En-tete -->
      <div class="page-head">
        <div>
          <h1 class="page-title">Mes bulletins de paie</h1>
          <p class="page-subtitle">Consultez et téléchargez vos bulletins de salaire.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">
          {{ errorMessage() }}
        </div>
      }
      @if (infoMessage()) {
        <div class="alert alert-info">
          {{ infoMessage() }}
        </div>
      }

      <!-- Filtres -->
      <div class="card p-4 flex flex-wrap items-end gap-3">
        <div>
          <label class="label">Mois</label>
          <select [(ngModel)]="selectedMonth" class="select w-auto">
            <option [ngValue]="0">Tous les mois</option>
            @for (m of months; track m.value) {
              <option [ngValue]="m.value">{{ m.label }}</option>
            }
          </select>
        </div>
        <div>
          <label class="label">Année</label>
          <select [(ngModel)]="selectedYear" class="select w-auto">
            <option [ngValue]="0">Toutes les années</option>
            @for (y of years; track y) {
              <option [ngValue]="y">{{ y }}</option>
            }
          </select>
        </div>
        <button (click)="loadPayslips()" class="btn btn-primary">
          Filtrer
        </button>
      </div>

      <!-- Tableau -->
      <div class="card overflow-hidden">
        <table class="data-table">
          <thead>
            <tr>
              <th>Période</th>
              <th class="text-right">Brut</th>
              <th class="text-right">Cotisations</th>
              <th class="text-right">Net à payer</th>
              <th>Statut</th>
              <th class="text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            @for (p of payslips(); track p.id) {
              <tr>
                <td class="px-4 py-3.5 font-medium text-slate-800">{{ formatPeriod(p) }}</td>
                <td class="px-4 py-3.5 num">{{ formatAmount(p.gross_amount) }}</td>
                <td class="px-4 py-3.5 num">{{ formatAmount(p.total_taxes) }}</td>
                <td class="px-4 py-3.5 num font-semibold text-emerald-700">{{ formatAmount(p.net_amount) }}</td>
                <td class="px-4 py-3.5">
                  <span [class]="statusBadge(p.status)">
                    {{ statusLabel(p.status) }}
                  </span>
                </td>
                <td class="px-4 py-3.5 text-right">
                  <button (click)="downloadPdf(p.id)" [disabled]="downloading() === p.id"
                          class="btn btn-sm btn-secondary disabled:opacity-50">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
                    {{ downloading() === p.id ? '...' : 'PDF' }}
                  </button>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="6" class="px-4 py-8 text-center text-slate-400">Aucun bulletin pour la période sélectionnée.</td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>
  `
})
export class MyPayslipsComponent implements OnInit {
    private apiService = inject(ApiService);

    payslips = signal<Payslip[]>([]);
    errorMessage = signal('');
    infoMessage = signal('');
    downloading = signal<number | null>(null);

    selectedMonth = 0;
    selectedYear = 0;
    months = Array.from({ length: 12 }, (_, i) => ({
        value: i + 1,
        label: new Date(2026, i, 1).toLocaleDateString('fr-FR', { month: 'long' })
    }));
    years = this.buildYears();

    ngOnInit(): void {
        this.loadPayslips();
    }

    loadPayslips(): void {
        this.errorMessage.set('');
        this.infoMessage.set('');
        const month = this.selectedMonth || undefined;
        const year = this.selectedYear || undefined;
        this.apiService.getMyPayslips(month, year).subscribe({
            next: (data) => {
                this.payslips.set(data);
                if (data.length === 0) {
                    this.infoMessage.set('Aucun bulletin trouvé. Contactez la paie si besoin.');
                }
            },
            error: (err) => {
                this.payslips.set([]);
                this.errorMessage.set(this.extractError(err) || 'Impossible de charger vos bulletins.');
            }
        });
    }

    downloadPdf(id: number): void {
        this.downloading.set(id);
        this.errorMessage.set('');
        this.apiService.getMyPayslipPdf(id).subscribe({
            next: (blob) => {
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `bulletin_${id}.pdf`;
                a.click();
                window.URL.revokeObjectURL(url);
                this.downloading.set(null);
            },
            error: (err) => {
                this.downloading.set(null);
                this.errorMessage.set(this.extractError(err) || 'Erreur lors du téléchargement du PDF.');
            }
        });
    }

    formatPeriod(p: Payslip): string {
        const start = new Date(p.period_start);
        const end = new Date(p.period_end);
        return `${start.toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' })}`
    }

    formatAmount(v: number): string {
        return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(v);
    }

    statusLabel(s: string): string {
        const map: Record<string, string> = {
            brouillon: 'Brouillon', soumis: 'Soumis', approuve: 'Approuvé',
            rejete: 'Rejeté', paye: 'Payé'
        };
        return map[s] || s;
    }

    statusBadge(s: string): string {
        const map: Record<string, string> = {
            brouillon: 'badge badge-slate',
            soumis: 'badge badge-amber',
            approuve: 'badge badge-blue',
            rejete: 'badge badge-rose',
            paye: 'badge badge-emerald'
        };
        return map[s] || 'badge badge-slate';
    }

    private buildYears(): number[] {
        const current = new Date().getFullYear();
        return [current - 1, current, current + 1];
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
