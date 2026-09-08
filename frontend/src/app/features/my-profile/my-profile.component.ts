import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { Employee, ProfileChangeRequest } from '../../core/models/kpay.models';

@Component({
    selector: 'app-my-profile',
    standalone: true,
    imports: [FormsModule, CommonModule],
    template: `
    <div class="space-y-6">
      <!-- En-tete -->
      <div class="page-head">
        <div>
          <h1 class="page-title">Mon profil</h1>
          <p class="page-subtitle">Modifications soumises, puis validées par la RH avant application.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">
          {{ errorMessage() }}
        </div>
      }
      @if (infoMessage()) {
        <div class="alert alert-success">
          {{ infoMessage() }}
        </div>
      }

      <div class="grid lg:grid-cols-2 gap-6">
        <!-- Informations actuelles -->
        <div class="card overflow-hidden">
          <div class="card-head">
            <h2 class="card-title">Informations actuelles</h2>
          </div>
          <dl class="px-6 py-4 space-y-3 text-sm">
            <div class="flex justify-between"><dt class="text-slate-500">Nom</dt><dd class="font-medium text-slate-800">{{ profile()?.first_name }} {{ profile()?.last_name }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Email</dt><dd class="font-medium text-slate-800">{{ profile()?.email }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Parts fiscales</dt><dd class="font-medium text-slate-800 tabular-nums">{{ profile()?.tax_parts }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">BIC</dt><dd class="font-medium text-slate-800">{{ profile()?.bic || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">IBAN</dt><dd class="font-mono text-slate-800">{{ profile()?.iban || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Téléphone</dt><dd class="font-medium text-slate-800">{{ profile()?.phone || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Adresse</dt><dd class="font-medium text-slate-800">{{ profile()?.address || '—' }}</dd></div>
          </dl>
        </div>

        <!-- Demander une modification -->
        <div class="card overflow-hidden">
          <div class="card-head">
            <h2 class="card-title">Demander une modification</h2>
          </div>
          <form class="px-6 py-4 space-y-4" (ngSubmit)="submitRequest()">
            <div>
              <label class="label">Champ à modifier</label>
              <select [(ngModel)]="selectedField" name="field" class="select">
                <option value="iban">IBAN</option>
                <option value="bic">BIC</option>
                <option value="phone">Téléphone</option>
                <option value="address">Adresse postale</option>
                <option value="tax_parts">Parts fiscales (ex: 1.0, 1.5, 2.0)</option>
              </select>
            </div>
            <div>
              <label class="label">Nouvelle valeur</label>
              <input [(ngModel)]="newValue" name="value" type="text" class="input" placeholder="Nouvelle valeur"/>
            </div>
            <button type="submit" [disabled]="submitting()" class="btn btn-primary w-full disabled:opacity-50">
              {{ submitting() ? 'Envoi...' : 'Soumettre la demande (validation RH requise)' }}
            </button>
            <p class="text-xs text-slate-500 text-center">La modification ne s'appliquera qu'après validation RH.</p>
          </form>
        </div>
      </div>

      <!-- Historique des demandes -->
      <div class="card overflow-hidden">
        <div class="card-head">
          <h2 class="card-title">Historique de mes demandes</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Champ</th>
                <th>Avant</th>
                <th>Après</th>
                <th>Statut</th>
                <th>Motif / Réviseur</th>
              </tr>
            </thead>
            <tbody>
              @for (req of requests(); track req.id) {
                <tr>
                  <td class="px-4 py-3.5 whitespace-nowrap">{{ formatDate(req.requested_at) }}</td>
                  <td class="px-4 py-3.5 font-medium text-slate-800">{{ fieldLabel(req.field_name) }}</td>
                  <td class="px-4 py-3.5">{{ req.old_value || '—' }}</td>
                  <td class="px-4 py-3.5 font-medium">{{ req.new_value }}</td>
                  <td class="px-4 py-3.5">
                    <span [class]="statusBadge(req.status)">{{ statusLabel(req.status) }}</span>
                  </td>
                  <td class="px-4 py-3.5 text-slate-500">
                    @if (req.status === 'refuse') { {{ req.rejection_reason }} }
                    @if (req.status === 'approuve' && req.reviewed_by) { par {{ req.reviewed_by }} }
                    @if (req.status === 'en_attente') { en attente }
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
export class MyProfileComponent implements OnInit {
    private apiService = inject(ApiService);

    profile = signal<Employee | null>(null);
    requests = signal<ProfileChangeRequest[]>([]);
    errorMessage = signal('');
    infoMessage = signal('');
    submitting = signal(false);

    selectedField = 'iban';
    newValue = '';

    ngOnInit(): void {
        this.loadProfile();
        this.loadRequests();
    }

    loadProfile(): void {
        this.apiService.getMe().subscribe({
            next: (emp) => this.profile.set(emp),
            error: (err) => this.errorMessage.set(this.extractError(err) || 'Impossible de charger votre profil.')
        });
    }

    loadRequests(): void {
        this.apiService.getMyProfileRequests().subscribe({
            next: (data) => this.requests.set(data),
            error: () => this.requests.set([])
        });
    }

    submitRequest(): void {
        this.errorMessage.set('');
        this.infoMessage.set('');
        if (!this.newValue.trim()) { this.errorMessage.set('Saisissez une nouvelle valeur.'); return; }
        this.submitting.set(true);
        this.apiService.requestProfileChange(this.selectedField, this.newValue.trim()).subscribe({
            next: () => {
                this.submitting.set(false);
                this.newValue = '';
                this.infoMessage.set('Votre demande est en cours de validation par la RH.');
                this.loadProfile();
                this.loadRequests();
            },
            error: (err) => {
                this.submitting.set(false);
                this.errorMessage.set(this.extractError(err) || 'Erreur lors de la soumission de la demande.');
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