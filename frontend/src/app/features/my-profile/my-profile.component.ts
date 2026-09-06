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
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Mon profil</h1>
          <p class="text-slate-500 text-sm">Modifications soumises, puis validées par la RH avant application.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">
          {{ errorMessage() }}
        </div>
      }
      @if (infoMessage()) {
        <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg text-sm">
          {{ infoMessage() }}
        </div>
      }

      <div class="grid lg:grid-cols-2 gap-6">
        <!-- Informations actuelles -->
        <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
          <div class="px-6 py-4 border-b border-slate-200 bg-slate-50">
            <h2 class="font-semibold text-slate-800">Informations actuelles</h2>
          </div>
          <dl class="px-6 py-4 space-y-3 text-sm">
            <div class="flex justify-between"><dt class="text-slate-500">Nom</dt><dd class="font-medium text-slate-800">{{ profile()?.first_name }} {{ profile()?.last_name }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Email</dt><dd class="font-medium text-slate-800">{{ profile()?.email }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Parts fiscales</dt><dd class="font-medium text-slate-800">{{ profile()?.tax_parts }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">BIC</dt><dd class="font-medium text-slate-800">{{ profile()?.bic || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">IBAN</dt><dd class="font-mono text-slate-800">{{ profile()?.iban || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Téléphone</dt><dd class="font-medium text-slate-800">{{ profile()?.phone || '—' }}</dd></div>
            <div class="flex justify-between"><dt class="text-slate-500">Adresse</dt><dd class="font-medium text-slate-800">{{ profile()?.address || '—' }}</dd></div>
          </dl>
        </div>

        <!-- Demander une modification -->
        <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
          <div class="px-6 py-4 border-b border-slate-200 bg-slate-50">
            <h2 class="font-semibold text-slate-800">Demander une modification</h2>
          </div>
          <form class="px-6 py-4 space-y-4" (ngSubmit)="submitRequest()">
            <div>
              <label class="block text-xs font-medium text-slate-500 mb-1">Champ à modifier</label>
              <select [(ngModel)]="selectedField" name="field" class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm bg-white">
                <option value="iban">IBAN</option>
                <option value="bic">BIC</option>
                <option value="phone">Téléphone</option>
                <option value="address">Adresse postale</option>
                <option value="tax_parts">Parts fiscales (ex: 1.0, 1.5, 2.0)</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-500 mb-1">Nouvelle valeur</label>
              <input [(ngModel)]="newValue" name="value" type="text"
                     class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                     placeholder="Nouvelle valeur" />
            </div>
            <button type="submit" [disabled]="submitting()"
                    class="w-full px-4 py-2.5 text-sm font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition disabled:opacity-50">
              {{ submitting() ? 'Envoi...' : 'Soumettre la demande (validation RH requise)' }}
            </button>
            <p class="text-xs text-slate-500 text-center">La modification ne s'appliquera qu'après validation RH.</p>
          </form>
        </div>
      </div>

      <!-- Historique des demandes -->
      <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <div class="px-6 py-4 border-b border-slate-200 bg-slate-50">
          <h2 class="font-semibold text-slate-800">Historique de mes demandes</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm text-slate-600">
            <thead class="bg-slate-50 text-slate-700 uppercase font-semibold text-xs border-b border-slate-200">
              <tr>
                <th class="px-6 py-3.5">Date</th>
                <th class="px-6 py-3.5">Champ</th>
                <th class="px-6 py-3.5">Avant</th>
                <th class="px-6 py-3.5">Après</th>
                <th class="px-6 py-3.5">Statut</th>
                <th class="px-6 py-3.5">Motif / Réviseur</th>
              </tr>
            </thead>
            <tbody class="divide-y border-slate-100">
              @for (req of requests(); track req.id) {
                <tr class="hover:bg-slate-50 transition">
                  <td class="px-6 py-4">{{ formatDate(req.requested_at) }}</td>
                  <td class="px-6 py-4 font-medium text-slate-800">{{ fieldLabel(req.field_name) }}</td>
                  <td class="px-6 py-4">{{ req.old_value || '—' }}</td>
                  <td class="px-6 py-4 font-medium">{{ req.new_value }}</td>
                  <td class="px-6 py-4">
                    <span [class]="statusBadge(req.status)">{{ statusLabel(req.status) }}</span>
                  </td>
                  <td class="px-6 py-4 text-slate-500">
                    @if (req.status === 'refuse') { {{ req.rejection_reason }} }
                    @if (req.status === 'approuve' && req.reviewed_by) { par {{ req.reviewed_by }} }
                    @if (req.status === 'en_attente') { en attente }
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