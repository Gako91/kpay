import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { DatePipe, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ChainCheck, DeclarationExport, DisaIssue, DisaPreview } from '../../core/models/kpay.models';

// Déclarations sociales (Pilier 5.1) : aperçu et export DISA annuel (fichier E-DISA),
// registre des déclarations scellées et vérification de son intégrité.
@Component({
    selector: 'app-declarations',
    standalone: true,
    imports: [FormsModule, DecimalPipe, DatePipe, RouterLink],
    template: `
    <div class="space-y-6">
      <div class="page-head">
        <div>
          <h1 class="page-title">Déclarations sociales</h1>
          <p class="page-subtitle">DISA annuelle CNPS : fichier d'entrée E-DISA (.xls) et registre scellé des exports.</p>
        </div>
        <div class="flex items-center gap-2">
          <select [(ngModel)]="year" name="year" (ngModelChange)="loadPreview()" class="select w-auto">
            @for (y of years; track y) {
              <option [ngValue]="y">{{ y }}</option>
            }
          </select>
          <button (click)="exportDisa()" [disabled]="!canExport() || busy()" class="btn btn-primary disabled:opacity-50">
            Générer la DISA {{ year }}
          </button>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      @if (preview(); as p) {
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div class="kpi-card">
            <p class="kpi-label">Salariés déclarés</p>
            <p class="kpi-value">{{ p.employees }}</p>
          </div>
          <div class="kpi-card">
            <p class="kpi-label">Masse salariale brute {{ p.year }}</p>
            <p class="kpi-value">{{ p.total_gross | number:'1.0-0' }} FCFA</p>
          </div>
          <div class="kpi-card">
            <p class="kpi-label">Anomalies bloquantes</p>
            <p class="kpi-value" [class.text-rose-600]="p.blocking_count > 0">{{ p.blocking_count }}</p>
          </div>
        </div>

        @if (p.issues.length > 0) {
          <div class="card overflow-hidden">
            <div class="card-head">
              <h2 class="card-title">Anomalies à corriger</h2>
            </div>
            <table class="data-table">
              <thead>
                <tr><th>Salarié</th><th>Donnée</th><th>Anomalie</th><th></th></tr>
              </thead>
              <tbody>
                @for (i of p.issues; track $index) {
                  <tr>
                    <td class="px-4 py-3 font-medium text-slate-900">{{ i.employee_name }}</td>
                    <td class="px-4 py-3 text-slate-500">{{ fieldLabel(i) }}</td>
                    <td class="px-4 py-3">{{ i.message }}</td>
                    <td class="px-4 py-3 text-right">
                      <span [class]="i.blocking ? 'badge badge-rose' : 'badge badge-amber'">
                        {{ i.blocking ? 'Bloquant' : 'Avertissement' }}
                      </span>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
            <p class="px-4 py-3 text-xs text-slate-400 border-t border-slate-100">
              Les données des salariés se corrigent depuis la page <a routerLink="/employees" class="text-blue-600 hover:underline">Employés</a> ;
              les bulletins en attente depuis la <a routerLink="/payroll" class="text-blue-600 hover:underline">Gestion de la Paie</a>.
            </p>
          </div>
        }

        <div class="card overflow-x-auto">
          <div class="card-head">
            <h2 class="card-title">Aperçu du fichier E-DISA</h2>
          </div>
          <table class="data-table">
            <thead>
              <tr>
                <th>N° CNPS</th><th>Nom</th><th>Prénoms</th><th>Naissance</th><th>Embauche</th>
                <th>Départ</th><th>Type</th><th class="num">Temps</th><th class="num">Brut annuel</th>
              </tr>
            </thead>
            <tbody>
              @for (r of p.rows; track r.employee_id) {
                <tr>
                  <td class="px-4 py-3 font-mono text-xs">{{ r.cnps_number || '—' }}</td>
                  <td class="px-4 py-3 font-medium text-slate-900">{{ r.last_name }}</td>
                  <td class="px-4 py-3">{{ r.first_names }}</td>
                  <td class="px-4 py-3">{{ r.birth_date || '—' }}</td>
                  <td class="px-4 py-3">{{ r.hire_date || '—' }}</td>
                  <td class="px-4 py-3">{{ r.departure_date }}</td>
                  <td class="px-4 py-3">{{ r.salary_type }}</td>
                  <td class="px-4 py-3 num">{{ r.work_time }}</td>
                  <td class="px-4 py-3 num">{{ r.annual_gross | number:'1.0-0' }}</td>
                </tr>
              } @empty {
                <tr>
                  <td colspan="9" class="px-4 py-8 text-center text-slate-400">Aucun bulletin validé en {{ p.year }}.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }

      <div class="card overflow-x-auto">
        <div class="card-head flex items-center justify-between">
          <h2 class="card-title">Registre des déclarations scellées</h2>
          <div class="flex items-center gap-2">
            @if (chain(); as c) {
              <span [class]="c.ok ? 'badge badge-emerald' : 'badge badge-rose'">
                {{ c.ok ? 'Intégrité vérifiée (' + c.entries + ')' : 'Registre altéré (entrée #' + c.broken_id + ')' }}
              </span>
            }
            <button (click)="verify()" class="btn btn-secondary btn-sm">Vérifier l'intégrité</button>
          </div>
        </div>
        @if (chain(); as c) {
          @if (!c.ok) {
            <div class="alert alert-error m-4">{{ c.reason }}</div>
          }
        }
        <table class="data-table">
          <thead>
            <tr>
              <th>Type</th><th>Période</th><th>Version</th><th>Scellé le</th><th>Par</th>
              <th class="num">Salariés</th><th class="num">Brut déclaré</th><th>Empreinte SHA-256</th><th></th>
            </tr>
          </thead>
          <tbody>
            @for (d of declarations(); track d.id) {
              <tr>
                <td class="px-4 py-3 uppercase font-medium">{{ d.kind }}</td>
                <td class="px-4 py-3">{{ d.period }}</td>
                <td class="px-4 py-3">v{{ d.version }}</td>
                <td class="px-4 py-3">{{ d.sealed_at | date:'dd/MM/yyyy HH:mm' }}</td>
                <td class="px-4 py-3">{{ d.created_by }}</td>
                <td class="px-4 py-3 num">{{ d.row_count }}</td>
                <td class="px-4 py-3 num">{{ d.total_amount | number:'1.0-0' }}</td>
                <td class="px-4 py-3 font-mono text-xs text-slate-400" [title]="d.sha256">{{ d.sha256.slice(0, 16) }}…</td>
                <td class="px-4 py-3 text-right">
                  <button (click)="download(d)" class="btn btn-secondary btn-sm">Télécharger</button>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="9" class="px-4 py-8 text-center text-slate-400">Aucune déclaration scellée pour le moment.</td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    </div>
  `
})
export class DeclarationsComponent implements OnInit {
    private api = inject(ApiService);

    // La DISA de l'année N se dépose au début de l'année N+1 : année précédente par défaut.
    private currentYear = new Date().getFullYear();
    years = [this.currentYear, this.currentYear - 1, this.currentYear - 2];
    year = this.currentYear - 1;

    preview = signal<DisaPreview | null>(null);
    declarations = signal<DeclarationExport[]>([]);
    chain = signal<ChainCheck | null>(null);
    busy = signal(false);
    errorMessage = signal('');
    successMessage = signal('');

    canExport = computed(() => {
        const p = this.preview();
        return !!p && p.blocking_count === 0 && p.rows.length > 0;
    });

    private fieldLabels: Record<string, string> = {
        cnps_number: 'N° CNPS',
        last_name: 'Nom',
        first_name: 'Prénoms',
        birth_date: 'Date de naissance',
        contract: 'Contrat',
        work_time: 'Temps de travail',
        salary_type: 'Périodicité',
        annual_gross: 'Brut annuel',
        bulletins: 'Bulletins'
    };

    ngOnInit(): void {
        this.loadPreview();
        this.loadDeclarations();
    }

    fieldLabel(i: DisaIssue): string {
        return this.fieldLabels[i.field] || i.field;
    }

    loadPreview(): void {
        this.errorMessage.set('');
        this.api.getDisaPreview(this.year).subscribe({
            next: (p) => this.preview.set(p),
            error: (err) => {
                this.preview.set(null);
                this.errorMessage.set(err?.error?.error || 'Impossible de préparer la DISA.');
            }
        });
    }

    loadDeclarations(): void {
        this.api.getDeclarations().subscribe({
            next: (list) => this.declarations.set(list),
            error: () => this.declarations.set([])
        });
    }

    exportDisa(): void {
        this.busy.set(true);
        this.errorMessage.set('');
        this.successMessage.set('');
        this.api.exportDisa(this.year).subscribe({
            next: (res) => {
                this.busy.set(false);
                const d = res.declaration;
                this.successMessage.set(`DISA ${d.period} v${d.version} scellée : ${d.row_count} salariés, empreinte ${d.sha256.slice(0, 16)}…`);
                this.loadDeclarations();
                this.chain.set(null);
                this.download(d);
            },
            error: (err) => {
                this.busy.set(false);
                // 422 : anomalies bloquantes renvoyées sous forme d'aperçu
                if (err?.status === 422 && err?.error?.issues) {
                    this.preview.set(err.error as DisaPreview);
                    this.errorMessage.set('Export refusé : corrigez les anomalies bloquantes.');
                } else {
                    this.errorMessage.set(err?.error?.error || 'Erreur lors de la génération de la DISA.');
                }
            }
        });
    }

    verify(): void {
        this.api.verifyDeclarations().subscribe({
            next: (c) => this.chain.set(c),
            error: () => this.errorMessage.set('Vérification du registre impossible.')
        });
    }

    download(d: DeclarationExport): void {
        this.api.downloadDeclaration(d.id).subscribe({
            next: (blob) => {
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = d.file_name.replace('.xls', `_v${d.version}.xls`);
                a.click();
                URL.revokeObjectURL(url);
            },
            error: (err) => {
                this.errorMessage.set(err?.status === 409
                    ? `Intégrité compromise : le fichier archivé de la déclaration #${d.id} ne correspond plus à son empreinte.`
                    : 'Téléchargement impossible.');
            }
        });
    }
}
