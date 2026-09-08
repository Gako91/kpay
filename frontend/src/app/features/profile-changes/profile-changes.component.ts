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
      <div class="page-head">
        <div>
          <h1 class="page-title">Validation RH — Modifications de profil</h1>
          <p class="page-subtitle">Les modifications ne sont appliquées au dossier employé qu'après validation.</p>
        </div>
        <div class="flex items-center gap-2">
          <button (click)="filterStatus('')" class="chip" [class]="statusFilter() === '' ? 'chip-active' : 'chip-idle'">Toutes</button>
          <button (click)="filterStatus('en_attente')" class="chip" [class]="statusFilter() === 'en_attente' ? 'chip-active' : 'chip-idle'">En attente</button>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (infoMessage()) {
        <div class="alert alert-success">{{ infoMessage() }}</div>
      }

      <div class="card overflow-hidden">
        <div class="overflow-x-auto">
          <table class="data-table">
            <thead>
              <tr>
                <th>Demande</th>
                <th>Employé</th>
                <th>Champ</th>
                <th>Actuel → Demandé</th>
                <th>Statut</th>
                <th class="text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              @for (req of requests(); track req.id) {
                <tr class="align-top">
                  <td class="px-4 py-3.5">
                    <p class="font-medium text-slate-800">#{{ req.id }}</p>
                    <p class="text-xs text-slate-400">{{ formatDate(req.requested_at) }}</p>
                  </td>
                  <td class="px-4 py-3.5">
                    @if (employeeMap()[req.employee_id]) {
                      <span class="font-medium text-slate-800">{{ employeeMap()[req.employee_id].first_name }} {{ employeeMap()[req.employee_id].last_name }}</span>
                      <p class="text-xs text-slate-400">{{ employeeMap()[req.employee_id].email }}</p>
                    } @else {
                      <span>Employé #{{ req.employee_id }}</span>
                    }
                  </td>
                  <td class="px-4 py-3.5">{{ fieldLabel(req.field_name) }}</td>
                  <td class="px-4 py-3.5">
                    <span class="line-through text-slate-400">{{ req.old_value || '—' }}</span>
                    <span class="mx-1 text-slate-300">→</span>
                    <span class="font-medium text-slate-900">{{ req.new_value }}</span>
                  </td>
                  <td class="px-4 py-3.5">
                    <span [class]="statusBadge(req.status)">{{ statusLabel(req.status) }}</span>
                    @if (req.status === 'refuse' && req.rejection_reason) {
                      <p class="text-xs text-rose-600 mt-1">Motif : {{ req.rejection_reason }}</p>
                    }
                    @if (req.reviewed_by) {
                      <p class="text-xs text-slate-400 mt-1">par {{ req.reviewed_by }}</p>
                    }
                  </td>
                  <td class="px-4 py-3.5 text-right whitespace-nowrap">
                    @if (req.status === 'en_attente') {
                      <button (click)="approve(req.id)" [disabled]="busy() === req.id" class="btn btn-sm btn-secondary mr-2 disabled:opacity-50">
                        Valider
                      </button>
                      <button (click)="reject(req.id)" [disabled]="busy() === req.id" class="btn btn-sm btn-danger disabled:opacity-50">
                        Refuser
                      </button>
                    } @else {
                      <span class="text-xs text-slate-400">Traité</span>
                    }
                  </td>
                </tr>
              } @empty {
                <tr><td colspan="6" class="px-4 py-8 text-center text-slate-400">Aucune demande de modification.</td></tr>
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
        const map: Record<string, string> = {
            en_attente: 'badge badge-amber',
            approuve: 'badge badge-emerald',
            refuse: 'badge badge-rose'
        };
        return map[s] || 'badge badge-slate';
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