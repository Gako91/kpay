import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { TaxComponent, TaxBracket, TaxImpactRequest, TaxImpactResponse, TaxLine } from '../../core/models/kpay.models';

@Component({
    selector: 'app-tax-rules',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6">
      <div class="page-head">
        <div>
          <h1 class="page-title">Règles sociales</h1>
          <p class="page-subtitle">Moteur de cotisations dynamique : composantes, barèmes (CN / IGR) et simulation d'impact avant / après.</p>
        </div>
        <button (click)="openCreateComponent()" class="btn btn-primary">
          + Nouvelle composante
        </button>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      @if (!canEdit()) {
        <div class="alert alert-info">
          Accès restreint aux administrateurs et comptables. Consultation seule : la configuration n'est pas modifiable dans cette session.
        </div>
      }

      <!-- Onglets -->
      <div class="flex gap-2">
        <button (click)="tab.set('components')" class="chip" [class]="tab() === 'components' ? 'chip-active' : 'chip-idle'">
          Composantes
        </button>
        <button (click)="tab.set('brackets')" class="chip" [class]="tab() === 'brackets' ? 'chip-active' : 'chip-idle'">
          Barèmes CN / IGR
        </button>
        <button (click)="tab.set('simulator')" class="chip" [class]="tab() === 'simulator' ? 'chip-active' : 'chip-idle'">
          Simulateur d'impact
        </button>
      </div>

      @if (tab() === 'components') {
        <!-- Composantes -->
        <div class="card overflow-hidden">
          <table class="data-table">
            <thead>
              <tr>
                <th>Code</th>
                <th>Libellé</th>
                <th class="text-right">Taux</th>
                <th>Assiette</th>
                <th>Plafond / Forfait</th>
                <th>Part</th>
                <th>Effet</th>
                <th>Actif</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              @for (c of components(); track c.id) {
                <tr>
                  <td class="px-4 py-3.5 font-mono text-xs text-slate-500">{{ c.code }}</td>
                  <td class="px-4 py-3.5 font-medium text-slate-900">{{ c.name }}</td>
                  <td class="px-4 py-3.5 num">{{ fmtRate(c.rate) }}</td>
                  <td class="px-4 py-3.5">{{ basisLabel(c.basis_type) }}</td>
                  <td class="px-4 py-3.5">{{ c.cap ? fmtInt(c.cap) + ' F' : (c.fixed_amount ? fmtInt(c.fixed_amount) + ' F fixe' : '—') }}</td>
                  <td class="px-4 py-3.5">{{ shareLabel(c.share) }}</td>
                  <td class="px-4 py-3.5">{{ c.effective_from || 'toujours' }}</td>
                  <td class="px-4 py-3.5">
                    <span [class]="c.is_active ? 'badge badge-emerald' : 'badge badge-slate'">
                      {{ c.is_active ? 'Oui' : 'Non' }}
                    </span>
                  </td>
                  <td class="px-4 py-3.5">
                    <div class="flex gap-1.5 justify-end">
                      <button (click)="openEditComponent(c)" class="btn btn-sm btn-secondary" [attr.disabled]="!canEdit() ? '' : null">Modifier</button>
                      <button (click)="toggleComponent(c)" class="btn btn-sm" [class]="c.is_active ? 'btn-secondary' : 'btn-primary'">
                        {{ c.is_active ? 'Désactiver' : 'Activer' }}
                      </button>
                    </div>
                  </td>
                </tr>
              } @empty {
                <tr>
                  <td colspan="9" class="px-4 py-8 text-center text-slate-400">
                    Aucune composante configurée — la paie utilise le barème standard.
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }

      @if (tab() === 'brackets') {
        <!-- Barèmes -->
        <div class="flex gap-2 items-center">
          <button (click)="bracketCode.set('CN')" class="chip" [class]="bracketCode() === 'CN' ? 'chip-active' : 'chip-idle'">
            Contribution Nationale (CN)
          </button>
          <button (click)="bracketCode.set('IGR')" class="chip" [class]="bracketCode() === 'IGR' ? 'chip-active' : 'chip-idle'">
            Impôt Général sur le Revenu (IGR)
          </button>
          <button (click)="openCreateBracket()" class="btn btn-primary ml-auto">+ Tranche</button>
        </div>
        <div class="card overflow-hidden">
          <table class="data-table">
            <thead>
              <tr>
                <th class="text-right">Borne basse</th>
                <th class="text-right">Borne haute</th>
                <th class="text-right">Taux marginal</th>
                <th class="text-right">Constante (flat)</th>
                <th>Effet</th>
                <th>Actif</th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              @for (b of visibleBrackets(); track b.id) {
                <tr>
                  <td class="px-4 py-3.5 num font-mono text-xs">{{ fmtInt(b.lower_bound) }}</td>
                  <td class="px-4 py-3.5 num font-mono text-xs">{{ b.upper_bound === -1 ? '∞' : fmtInt(b.upper_bound) }}</td>
                  <td class="px-4 py-3.5 num">{{ fmtRate(b.rate) }}</td>
                  <td class="px-4 py-3.5 num font-mono text-xs">{{ fmtInt(b.flat) }}</td>
                  <td class="px-4 py-3.5">{{ b.effective_from || 'toujours' }}</td>
                  <td class="px-4 py-3.5">
                    <span [class]="b.is_active ? 'badge badge-emerald' : 'badge badge-slate'">
                      {{ b.is_active ? 'Oui' : 'Non' }}
                    </span>
                  </td>
                  <td class="px-4 py-3.5">
                    <div class="flex gap-1.5 justify-end">
                      <button (click)="openEditBracket(b)" class="btn btn-sm btn-secondary" [attr.disabled]="!canEdit() ? '' : null">Modifier</button>
                      <button (click)="toggleBracket(b)" class="btn btn-sm" [class]="b.is_active ? 'btn-secondary' : 'btn-primary'">
                        {{ b.is_active ? 'Désactiver' : 'Activer' }}
                      </button>
                    </div>
                  </td>
                </tr>
              } @empty {
                <tr>
                  <td colspan="7" class="px-4 py-8 text-center text-slate-400">Aucune tranche pour ce barème.</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
        <p class="text-xs text-slate-400">Montant dans une tranche = round(base × taux − constante). -1 en borne haute = non borné. Changer une borne imposée = versionner via « Effet » (nouvelle date), sinon rejet non-recouvrement.</p>
      }

      @if (tab() === 'simulator') {
        <!-- Simulateur -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div class="card p-5 space-y-4">
            <h2 class="card-title">Paramètres</h2>
            <div>
              <label class="label">Salaire brut simulé (FCFA)</label>
              <input type="number" [(ngModel)]="sim.gross" name="gross" class="input"/>
            </div>
            <div>
              <label class="label">Parts fiscales</label>
              <input type="number" step="0.5" min="1" [(ngModel)]="sim.tax_parts" name="parts" class="input"/>
            </div>
            <div>
              <label class="label">Période (YYYY-MM-DD)</label>
              <input type="text" [(ngModel)]="sim.period" name="period" placeholder="2026-09-01" class="input"/>
            </div>
            <div>
              <label class="label">Taux retraite salariale simulé (%)</label>
              <input type="number" step="0.1" [(ngModel)]="sim.retraite_rate_pct" name="retraite" class="input"/>
            </div>
            <button (click)="computeImpact()" class="btn btn-primary w-full">
              Simuler
            </button>
            <p class="text-xs text-slate-400">Seules les composantes sont transmises : le barème CN/IGR courant est conservé pour le scénario proposé.</p>
          </div>

          <div class="card p-5 space-y-3">
            <h2 class="card-title">Actuel</h2>
            @for (l of currentDetails(); track l.name) {
              <div class="flex justify-between text-sm">
                <span class="text-slate-600">{{ l.name }}</span>
                <span class="font-mono font-medium">{{ fmtInt(l.amount) }}</span>
              </div>
            }
            <div class="flex justify-between text-sm font-semibold border-t border-slate-100 pt-2">
              <span>Net</span>
              <span class="font-mono">{{ fmtInt(currentNet()) }}</span>
            </div>
          </div>

          <div class="card p-5 space-y-3">
            <h2 class="card-title">Proposé</h2>
            @for (l of proposedDetails(); track l.name) {
              <div class="flex justify-between text-sm">
                <span class="text-slate-600">{{ l.name }}</span>
                <span class="font-mono font-medium">{{ fmtInt(l.amount) }}</span>
              </div>
            }
            <div class="flex justify-between text-sm font-semibold border-t border-slate-100 pt-2">
              <span>Net</span>
              <span class="font-mono">{{ fmtInt(proposedNet()) }}</span>
            </div>
            <div class="flex items-center justify-between rounded-lg px-3 py-2 text-sm font-bold" [class]="(deltaNet()) >= 0 ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-700'">
              <span>Impact net</span>
              <span>{{ fmtSigned(deltaNet()) }}</span>
            </div>
          </div>
        </div>
      }

      <!-- Modale composante -->
      @if (showComponentModal()) {
        <div class="modal-overlay">
          <div class="modal">
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">{{ editComponentId() ? 'Modifier la composante' : 'Nouvelle composante' }}</h2>
            <form (ngSubmit)="saveComponent()" class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Code</label>
                  <input type="text" [(ngModel)]="formComponent.code" name="code" required class="input"/>
                </div>
                <div>
                  <label class="label">Libellé</label>
                  <input type="text" [(ngModel)]="formComponent.name" name="name" required class="input"/>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Taux (%)</label>
                  <input type="number" step="0.01" [(ngModel)]="formComponentRatePct" name="rate" class="input"/>
                </div>
                <div>
                  <label class="label">Assiette</label>
                  <select [(ngModel)]="formComponent.basis_type" name="basis" class="input">
                    <option value="brut">Brut</option>
                    <option value="brut80">80% du brut</option>
                    <option value="plafonne">Plafonnée</option>
                    <option value="forfait">Forfait</option>
                  </select>
                </div>
              </div>
              <div class="grid grid-cols-3 gap-4">
                <div>
                  <label class="label">Plafond (F)</label>
                  <input type="number" [(ngModel)]="formComponent.cap" name="cap" class="input"/>
                </div>
                <div>
                  <label class="label">Forfait (F)</label>
                  <input type="number" [(ngModel)]="formComponent.fixed_amount" name="fixed" class="input"/>
                </div>
                <div>
                  <label class="label">Part</label>
                  <select [(ngModel)]="formComponent.share" name="share" class="input">
                    <option value="salarial">Salariale</option>
                    <option value="patronal">Patronale</option>
                  </select>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
<label class="label">Date d'effet (vide = aujourd'hui en création, toujours en édition)</label>
                  <input type="date" [(ngModel)]="formComponent.effective_from" name="eff" class="input"/>
                </div>
                <div>
                  <label class="label">Pays</label>
                  <input type="text" [(ngModel)]="formComponent.country" name="country" class="input"/>
                </div>
              </div>
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="showComponentModal.set(false)" class="btn btn-secondary">Annuler</button>
                <button type="submit" class="btn btn-primary">Enregistrer</button>
              </div>
            </form>
          </div>
        </div>
      }

      <!-- Modale tranche -->
      @if (showBracketModal()) {
        <div class="modal-overlay">
          <div class="modal">
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">{{ editBracketId() ? 'Modifier la tranche' : 'Nouvelle tranche' }}</h2>
            <form (ngSubmit)="saveBracket()" class="space-y-4">
              <div>
                <label class="label">Barème</label>
                <select [(ngModel)]="formBracket.component_code" name="code" class="input">
                  <option value="CN">Contribution Nationale (CN)</option>
                  <option value="IGR">Impôt Général sur le Revenu (IGR)</option>
                </select>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Borne basse (F)</label>
                  <input type="number" [(ngModel)]="formBracket.lower_bound" name="lower" required class="input"/>
                </div>
                <div>
                  <label class="label">Borne haute (vide = ∞)</label>
                  <input type="number" [(ngModel)]="formBracketUpperRaw" name="upper" class="input"/>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Taux marginal (%)</label>
                  <input type="number" step="0.0001" [(ngModel)]="formBracketRatePct" name="rate" class="input"/>
                </div>
                <div>
                  <label class="label">Constante (flat, F)</label>
                  <input type="number" [(ngModel)]="formBracket.flat" name="flat" class="input"/>
                </div>
              </div>
              <div>
                <label class="label">Date d'effet (vide = toujours)</label>
                <input type="date" [(ngModel)]="formBracket.effective_from" name="eff" class="input"/>
              </div>
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="showBracketModal.set(false)" class="btn btn-secondary">Annuler</button>
                <button type="submit" class="btn btn-primary">Enregistrer</button>
              </div>
            </form>
          </div>
        </div>
      }
    </div>
  `
})
export class TaxRulesComponent implements OnInit {
    private apiService = inject(ApiService);
    private auth = inject(AuthService);

    components = signal<TaxComponent[]>([]);
    brackets = signal<TaxBracket[]>([]);
    tab = signal<'components' | 'brackets' | 'simulator'>('components');
    bracketCode = signal<'CN' | 'IGR'>('CN');

    errorMessage = signal('');
    successMessage = signal('');

    // Modale composante
    showComponentModal = signal(false);
    editComponentId = signal<number | null>(null);
    formComponent: Partial<TaxComponent> = {};
    formComponentRatePct = 0;

    // Modale tranche
    showBracketModal = signal(false);
    editBracketId = signal<number | null>(null);
    formBracket: Partial<TaxBracket> = {};
    formBracketRatePct = 0;
    formBracketUpperRaw: string = '';

    // Simulateur
    sim = { gross: 400000, tax_parts: 1, period: '', retraite_rate_pct: 6.3 };
    impact = signal<TaxImpactResponse | null>(null);

    get role(): string {
        return this.auth.currentUser()?.role || '';
    }

    canEdit(): boolean {
        return this.role === 'admin' || this.role === 'accountant';
    }

    ngOnInit(): void {
        this.loadComponents();
        this.loadBrackets();
        const today = new Date();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        this.sim.period = `${today.getFullYear()}-${mm}-${dd}`;
    }

    loadComponents(): void {
        this.apiService.getTaxComponents().subscribe({
            next: (list) => {
                this.components.set(list);
                const ret = list.find((c) => c.code === 'CNPS_RET' && c.share === 'salarial');
                if (ret) this.sim.retraite_rate_pct = +(ret.rate * 100).toFixed(3);
            },
            error: () => this.components.set([])
        });
    }

    loadBrackets(): void {
        this.apiService.getTaxBrackets().subscribe({
            next: (list) => this.brackets.set(list),
            error: () => this.brackets.set([])
        });
    }

    visibleBrackets(): TaxBracket[] {
        return this.brackets().filter((b) => b.component_code === this.bracketCode());
    }

    clearMessages(): void {
        this.errorMessage.set('');
        this.successMessage.set('');
    }

    basisLabel(b: string): string {
        const labels: Record<string, string> = { brut: 'Brut', brut80: '80% brut', plafonne: 'Plafonnée', forfait: 'Forfait' };
        return labels[b] || b;
    }

    shareLabel(s: string): string {
        return s === 'patronal' ? 'Patronale' : 'Salariale';
    }

    fmtInt(v: number): string {
        return new Intl.NumberFormat('fr-FR').format(Math.round(v || 0));
    }

    fmtSigned(v: number): string {
        const sign = v >= 0 ? '+' : '';
        return `${sign}${this.fmtInt(v)} F`;
    }

    fmtRate(rate: number): string {
        return `${(rate * 100).toFixed(3).replace(/\.?0+$/, '')}%`;
    }

    currentDetails(): TaxLine[] {
        return this.impact()?.current.details || [];
    }

    proposedDetails(): TaxLine[] {
        return this.impact()?.proposed.details || [];
    }

    currentNet(): number {
        return this.impact()?.current.net || 0;
    }

    proposedNet(): number {
        return this.impact()?.proposed.net || 0;
    }

    deltaNet(): number {
        return this.impact()?.delta_net || 0;
    }

    // --- Composantes ---
    openCreateComponent(): void {
        if (!this.canEdit()) return;
        this.editComponentId.set(null);
        this.formComponent = { code: '', name: '', rate: 0, basis_type: 'brut', cap: 0, fixed_amount: 0, share: 'salarial', is_active: true, country: 'CI', effective_from: '' };
        this.formComponentRatePct = 0;
        this.showComponentModal.set(true);
    }

    openEditComponent(c: TaxComponent): void {
        if (!this.canEdit()) return;
        this.editComponentId.set(c.id ?? null);
        this.formComponent = { ...c };
        this.formComponentRatePct = +(c.rate * 100).toFixed(6);
        this.showComponentModal.set(true);
    }

    saveComponent(): void {
        this.clearMessages();
        const payload: Partial<TaxComponent> = {
            code: this.formComponent.code,
            name: this.formComponent.name,
            rate: this.formComponentRatePct / 100,
            basis_type: this.formComponent.basis_type as TaxComponent['basis_type'],
            cap: this.formComponent.cap || 0,
            fixed_amount: this.formComponent.fixed_amount || 0,
            share: this.formComponent.share as TaxComponent['share'],
            effective_from: this.formComponent.effective_from || '',
            is_active: this.formComponent.is_active ?? true,
            country: this.formComponent.country || 'CI'
        };
        const done = () => {
            this.showComponentModal.set(false);
            this.successMessage.set(this.editComponentId() ? 'Composante mise à jour.' : 'Composante créée.');
            this.loadComponents();
        };
        const fails = (err: any) => this.errorMessage.set(this.extractError(err) || 'Erreur lors de l\'enregistrement.');
        if (this.editComponentId()) {
            this.apiService.updateTaxComponent(this.editComponentId()!, payload).subscribe({ next: done, error: fails });
        } else {
            this.apiService.createTaxComponent(payload).subscribe({ next: done, error: fails });
        }
    }

    toggleComponent(c: TaxComponent): void {
        if (!this.canEdit()) return;
        this.apiService.updateTaxComponent(c.id!, { ...c, is_active: !c.is_active }).subscribe({
            next: () => {
                this.successMessage.set(`Composante ${c.is_active ? 'désactivée' : 'activée'}.`);
                this.loadComponents();
            },
            error: (err) => this.errorMessage.set(this.extractError(err))
        });
    }

    // --- Tranches ---
    openCreateBracket(): void {
        if (!this.canEdit()) return;
        this.editBracketId.set(null);
        this.formBracket = { component_code: this.bracketCode(), lower_bound: 0, upper_bound: -1, rate: 0, flat: 0, is_active: true, effective_from: '' };
        this.formBracketRatePct = 0;
        this.formBracketUpperRaw = '';
        this.showBracketModal.set(true);
    }

    openEditBracket(b: TaxBracket): void {
        if (!this.canEdit()) return;
        this.editBracketId.set(b.id ?? null);
        this.formBracket = { ...b };
        this.formBracketRatePct = +(b.rate * 100).toFixed(6);
        this.formBracketUpperRaw = b.upper_bound === -1 ? '' : String(b.upper_bound);
        this.showBracketModal.set(true);
    }

    saveBracket(): void {
        this.clearMessages();
        const upper = this.formBracketUpperRaw.trim() === '' ? -1 : Number(this.formBracketUpperRaw);
        const payload: Partial<TaxBracket> = {
            component_code: this.formBracket.component_code as TaxBracket['component_code'],
            lower_bound: this.formBracket.lower_bound,
            upper_bound: upper,
            rate: this.formBracketRatePct / 100,
            flat: this.formBracket.flat || 0,
            effective_from: this.formBracket.effective_from || '',
            is_active: this.formBracket.is_active ?? true
        };
        const done = () => {
            this.showBracketModal.set(false);
            this.successMessage.set(this.editBracketId() ? 'Tranche mise à jour.' : 'Tranche créée.');
            this.loadBrackets();
        };
        const fails = (err: any) => this.errorMessage.set(this.extractError(err) || 'Erreur lors de l\'enregistrement.');
        if (this.editBracketId()) {
            this.apiService.updateTaxBracket(this.editBracketId()!, payload).subscribe({ next: done, error: fails });
        } else {
            this.apiService.createTaxBracket(payload).subscribe({ next: done, error: fails });
        }
    }

    toggleBracket(b: TaxBracket): void {
        if (!this.canEdit()) return;
        this.apiService.updateTaxBracket(b.id!, { ...b, is_active: !b.is_active }).subscribe({
            next: () => {
                this.successMessage.set(`Tranche ${b.is_active ? 'désactivée' : 'activée'}.`);
                this.loadBrackets();
            },
            error: (err) => this.errorMessage.set(this.extractError(err))
        });
    }

    // --- Simulateur ---
    computeImpact(): void {
        this.clearMessages();
        const request: TaxImpactRequest = {
            gross: this.sim.gross || 0,
            tax_parts: this.sim.tax_parts || 1,
            period: this.sim.period || undefined,
            components: this.components().map((c) => ({
                ...c,
                rate: c.code === 'CNPS_RET' && c.share === 'salarial' ? this.sim.retraite_rate_pct / 100 : c.rate
            }))
        };
        this.apiService.computeTaxImpact(request).subscribe({
            next: (res) => this.impact.set(res),
            error: (err) => this.errorMessage.set(this.extractError(err) || 'Erreur lors de la simulation.')
        });
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