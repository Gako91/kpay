import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';

@Component({
    selector: 'app-org-settings',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6 max-w-2xl">
      <div class="page-head">
        <div>
          <h1 class="page-title">Paramètres RH</h1>
          <p class="page-subtitle">Règles de carence et délai de déclaration des congés maladie, configurées par organisation.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      <div class="card p-6 space-y-5">
        <div>
          <label class="label">Jours de carence (congé maladie non rémunéré)</label>
          <input type="number" min="0" max="365" [(ngModel)]="carenceDays" name="carence" class="input" />
          <p class="text-xs text-slate-400 mt-1.5">Durée d'attente avant prise en charge d'un arrêt maladie. 0 = sans carence.</p>
        </div>

        <div>
          <label class="label">Délai de déclaration (jours)</label>
          <input type="number" min="0" max="365" [(ngModel)]="deadlineDays" name="deadline" class="input" />
          <p class="text-xs text-slate-400 mt-1.5">L'absence maladie doit être déclarée dans ce délai après sa date de début, au-delà la soumission est refusée.</p>
        </div>

        <div class="flex items-center gap-3 pt-2">
          <button (click)="save()" [disabled]="saving()" class="btn btn-primary">
            {{ saving() ? 'Enregistrement…' : 'Enregistrer les paramètres' }}
          </button>
          <button (click)="load()" class="btn btn-secondary" [disabled]="saving()">Recharger</button>
        </div>
      </div>
    </div>
  `
})
export class OrgSettingsComponent implements OnInit {
    api = inject(ApiService);

    carenceDays = 3;
    deadlineDays = 2;
    saving = signal(false);
    errorMessage = signal('');
    successMessage = signal('');

    ngOnInit() {
        this.load();
    }

    load() {
        this.errorMessage.set('');
        this.successMessage.set('');
        this.api.getOrgLeaveSettings().subscribe({
            next: (s) => {
                this.carenceDays = s.leave_carence_days ?? 3;
                this.deadlineDays = s.leave_declaration_deadline_days ?? 2;
            },
            error: () => this.errorMessage.set('Impossible de charger les paramètres de l\'organisation.')
        });
    }

    save() {
        const carence = Math.trunc(this.carenceDays) || 0;
        const deadline = Math.trunc(this.deadlineDays) || 0;
        if (carence < 0 || carence > 365 || deadline < 0 || deadline > 365) {
            this.errorMessage.set('Les valeurs doivent être comprises entre 0 et 365 jours.');
            return;
        }
        this.errorMessage.set('');
        this.successMessage.set('');
        this.saving.set(true);
        this.api.updateOrgLeaveSettings({ carence_days: carence, deadline_days: deadline }).subscribe({
            next: (res) => {
                this.saving.set(false);
                if (res.success) {
                    this.successMessage.set(res.message || 'Paramètres congés mis à jour.');
                } else {
                    this.errorMessage.set(res.message || 'Échec de la mise à jour.');
                }
            },
            error: (err) => {
                this.saving.set(false);
                this.errorMessage.set(err?.error?.error || err?.error?.message || 'Erreur lors de la mise à jour des paramètres.');
            }
        });
    }
}