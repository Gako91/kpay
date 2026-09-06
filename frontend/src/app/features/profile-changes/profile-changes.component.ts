import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { ProfileChangeRequest } from '../../core/models/kpay.models';

@Component({
    selector: 'app-profile-changes',
    standalone: true,
    imports: [FormsModule, CommonModule],
    template: `
    <div class="space-y-6">
      <!-- En-tete -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Validation RH — Modifications de profil</h1>
          <p class="text-slate-500 text-sm">Les modifications ne sont appliquées au dossier employé qu'après validation.</p>
        </div>
        <div class="flex items-center gap-2">
          <button (click)="filterStatus('')" [class]="statusFilter() === '' ? activeFilter : inactiveFilter">Toutes</button>
          <button (click)="filterStatus('en_attente')" [class]="statusFilter() === 'en_attente' ? activeFilter : inactiveFilter">En attente</button>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">{{ errorMessage() }}</div>
      }
      @if (infoMessage()) {
        <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg text-sm">{{ infoMessage() }}</div>
      }

      <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm text-slate-600">
            <thead class="bg-slate-50 text-slate-700 uppercase font-semibold text-xs border-b border-slate-200">
              <tr>
                <th class="px-6 py-3.5">Demande</th>
                <th class="px-6 py-3.5">Employé</th>
                <th class="px-6 py-3.5">Champ</th>
                <th class="px-6 py-3.5">Actuel → Demandé</th>
                <th class="px-6 py-3.5">Statut</th>
                <th class="px-6 py-3.5 text-right">Action</th>
              </tr>
            </thead>
            <tbody class="divide-y border-slate-100">
              @for (req of requests(); track req.id) {
                <tr class="hover:bg-slate-50 transition align-top">
                  <td class="px-6 py-4">
                    <p class="font-medium text-slate-800">#{{ req.id }}</p>
                    <p class="text-xs text-slate-400">{{ formatDate(req.requested_at) }}</p>
                  </td>
                  <td class="px-6 py-4">
                    @if (employeeMap()[req.employee_id]) {
                      <span class="font-medium text-slate-800">{{ employeeMap()[req.employee_id].first_name }} {{ employeeMap()[req.employee_id].last_name }}</span>
                      <p class="text-xs text-slate-400">{{ employeeMap()[req.employee_id].email }}</p>
                    } @else {
                      <span>Employé #{{ req.employee_id }}</span>
                    }
                  </td>
                  <td class="px-6 py-4">{{ fieldLabel(req.field_name) }}</td>
                  <td class="px-6 py-4">
                    <span class="line-through text-slate-400">{{ req.old_value || '—' }}</span>
                    <span class="mx-1 text-slate-300">→</span>
                    <span class="font-semibold text-emerald-700">{{ req.new_value }}</span>
                  </td>
                  <td class="px-6 py-4">
                    <span [class]="statusBadge(req.status)">{{ statusLabel(req.status) }}</span>
                    @if (req.status === 'refuse' && req.rejection_reason) {
                      <p class="text-xs text-rose-600 mt-1">Motif : {{ req.rejection_reason }}</p>
                    }
                    @if (req.reviewed_by) {
                      <p class="text-xs text-slate-400 mt-1">par {{ req.reviewed_by }}</p>
                    }
                  </td>
                  <td class="px-6 py-4 text-right whitespace-nowrap">
                    @if (req.status === 'en_attente') {
                      <button (click)="approve(req.id)" [disabled]="busy() === req.id"
                              class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium bg-emerald-50 text-emerald-700 hover:bg-emerald-100 rounded-lg transition disabled:opacity-50 mr-2">
                        Valider
                      </button>
                      <button (click)="reject(req.id)" [disabled]="busy() === req.id"
                              class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium bg-rose-50 text-rose-700 hover:bg-rose-100 rounded-lg transition disabled:opacity-50">
                        Refuser
                      </button>
                    } @else {
                      <span class="text-xs text-slate-400">Traité</span>
                    }
                  </td>
                </tr>
              } @empty {
                <tr><td colspan="6" class="px-6 py-8 text-center text-slate-400">Aucune demande de modification.</td></tr>
              }
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `
})
export class ProfileChangesComponent implements OnInit {
    private apiService = inject(ApiService);

    requests = signal<ProfileChangeRequest[]>([]);
    employeeMap = signal<Record<number, any>>({});
    statusFilter = signal('');
    errorMessage = signal('');
    infoMessage = signal('');
    busy = signal<number | null>(null);
    rejectReason = '';

    activeFilter = 'px-3 py-1.5 text-xs font-medium bg-blue-600 text-white rounded-lg';
    inactiveFilter = 'px-3 py-1.5 text-xs font-medium bg-slate-100 text-slate-600 hover:bg-slate-200 rounded-lg';

    ngOnInit(): void {
        this.loadEmployees();
        this.loadRequests();
    }

    loadRequests(): void {
        this.apiService.getProfileChanges(this.statusFilter() || undefined).subscribe({
            next: (data) => this.requests.set(data),
            error: (err) => this.errorMessage.set(this.extractError(err) || 'Impossible de charger les demandes.')
        });
    }

    loadEmployees(): void {
        this.apiService.getEmployees().subscribe({
            next: (emps) => {
                const map: Record<number, any> = {};
                for (const e of emps) map[e.id] = e;
                this.employeeMap.set(map);
            },
            error: () => { /* liste employés non bloquante */ }
        });
    }

    filterStatus(s: string): void {
        this.statusFilter.set(s);
        this.loadRequests();
    }

    approve(id: number): void {
        if (!confirm('Valider cette modification ? Elle sera appliquée au dossier employé.')) return;
        this.busy.set(id);
        this.errorMessage.set('');
        this.apiService.approveProfileChange(id).subscribe({
            next: () => {
                this.busy.set(null);
                this.infoMessage.set('Modification validée et appliquée.');
                this.loadRequests();
            },
            error: (err) => {
                this.busy.set(null);
                this.errorMessage.set(this.extractError(err) || 'Erreur lors de la validation.');
            }
        });
    }

    reject(id: number): void {
        const reason = prompt('Motif du refus (obligatoire) :');
        if (reason === null) return;
        if (!reason.trim()) { this.errorMessage.set('Un motif de refus est obligatoire.'); return; }
        this.busy.set(id);
        this.errorMessage.set('');
        this.apiService.rejectProfileChange(id, reason.trim()).subscribe({
            next: () => {
                this.busy.set(null);
                this.infoMessage.set('Demande refusée.');
                this.loadRequests();
            },
            error: (err) => {
                this.busy.set(null);
                this.errorMessage.set(this.extractError(err) || 'Erreur lors du refus.');
            }
        });
    }

    fieldLabel(f: string): string {
        const map: Record<string, string> = {
            iban: 'IBAN', bic: 'BIC', phone: 'Téléphone', address: 'Adresse postale', tax_parts: 'Parts fiscales'
        };
        return map[f] || f;
    }

    statusLabel(s: string): string {
        const map: Record<string, string> = { en_attente: 'En attente', approuve: 'Validé', refuse: 'Refusé' };
        return map[s] || s;
    }

    statusBadge(s: string): string {
        const base = 'inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium';
        const map: Record<string, string> = {
            en_attente: 'bg-amber-100 text-amber-800',
            approuve: 'bg-emerald-100 text-emerald-800',
            refuse: 'bg-rose-100 text-rose-700'
        };
        return `${base} ${map[s] || 'bg-slate-100 text-slate-700'}`;
    }

    formatDate(d: string): string {
        return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
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