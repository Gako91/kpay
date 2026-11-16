import { Component, EventEmitter, inject, Input, OnInit, Output, signal } from '@angular/core';
import { IconComponent } from '../../shared/icon.component';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { ApiService } from '../../core/services/api.service';
import { Adjustment, Contract, Employee, Timesheet } from '../../core/models/kpay.models';

type Tab = 'contracts' | 'adjustments' | 'timesheets';

const MONTHS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

// Dossier d'un salarié : contrats (création, avenant, clôture), primes et retenues
// mensuelles, relevés d'heures. Ces données alimentent le calcul de la paie.
@Component({
    selector: 'app-employee-file',
    standalone: true,
    imports: [FormsModule, DecimalPipe, IconComponent],
    template: `
    <div class="modal-overlay">
      <div class="modal max-w-3xl!">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">Dossier de {{ employee.first_name }} {{ employee.last_name }}</h2>
            <p class="text-sm text-slate-500">Ces éléments sont pris en compte au prochain calcul ou recalcul de la paie.</p>
          </div>
          <button (click)="closed.emit()" class="btn btn-secondary btn-sm">Fermer</button>
        </div>

        <div class="flex flex-wrap gap-2 mt-4">
          <button (click)="tab.set('contracts')" class="chip" [class]="tab() === 'contracts' ? 'chip-active' : 'chip-idle'">Contrats</button>
          <button (click)="tab.set('adjustments')" class="chip" [class]="tab() === 'adjustments' ? 'chip-active' : 'chip-idle'">Primes &amp; retenues</button>
          <button (click)="tab.set('timesheets')" class="chip" [class]="tab() === 'timesheets' ? 'chip-active' : 'chip-idle'">Heures</button>
        </div>

        @if (error()) {
          <div class="alert alert-error mt-4">{{ error() }}</div>
        }
        @if (success()) {
          <div class="alert alert-success mt-4">{{ success() }}</div>
        }

        <!-- ========== CONTRATS ========== -->
        @if (tab() === 'contracts') {
          <div class="overflow-x-auto mt-4"><table class="data-table">
            <thead>
              <tr><th>Début</th><th>Fin</th><th class="num">Salaire de base</th><th class="num">Taux horaire</th><th>Statut</th><th></th></tr>
            </thead>
            <tbody>
              @for (c of contracts(); track c.id) {
                <tr>
                  <td class="px-4 py-3">{{ day(c.start_date) }}</td>
                  <td class="px-4 py-3">{{ c.end_date ? day(c.end_date) : '—' }}</td>
                  <td class="px-4 py-3 num">{{ c.base_salary | number:'1.0-0' }}</td>
                  <td class="px-4 py-3 num">{{ c.hourly_rate | number:'1.0-0' }}</td>
                  <td class="px-4 py-3">
                    <span [class]="isOpen(c) ? 'badge badge-emerald' : 'badge badge-slate'">{{ isOpen(c) ? 'En cours' : 'Clos' }}</span>
                  </td>
                  <td class="px-4 py-3 text-right">
                    @if (isOpen(c) && canEdit) {
                      @if (closingId() === c.id) {
                        <div class="flex gap-1.5 justify-end items-center">
                          <input type="date" [(ngModel)]="closingDate" name="closingDate" class="input w-auto"/>
                          <button (click)="endContract(c)" class="btn btn-icon btn-danger" title="Confirmer la fin du contrat" aria-label="Confirmer la fin du contrat"><app-icon name="check"/></button>
                          <button (click)="closingId.set(null)" class="btn btn-icon btn-secondary" title="Annuler" aria-label="Annuler"><app-icon name="close"/></button>
                        </div>
                      } @else {
                        <button (click)="closingId.set(c.id); closingDate = ''" class="btn btn-icon btn-secondary" title="Clore le contrat…" aria-label="Clore le contrat…"><app-icon name="end"/></button>
                      }
                    }
                  </td>
                </tr>
              } @empty {
                <tr><td colspan="6" class="px-4 py-6 text-center text-slate-400">Aucun contrat : ce salarié ne sera pas payé.</td></tr>
              }
            </tbody>
          </table></div>

          @if (canEdit) {
            <form (ngSubmit)="createContract()" class="card p-4 mt-4 space-y-3">
              <h3 class="card-title">{{ contracts().length ? 'Nouveau contrat (avenant)' : 'Premier contrat' }}</h3>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <label class="label">Salaire de base mensuel (FCFA)</label>
                  <input type="number" min="1" [(ngModel)]="newContract.base_salary" name="base" required class="input"/>
                </div>
                <div>
                  <label class="label">Taux horaire (FCFA)</label>
                  <input type="number" min="0" [(ngModel)]="newContract.hourly_rate" name="hourly" class="input"/>
                </div>
                <div>
                  <label class="label">Date de début</label>
                  <input type="date" [(ngModel)]="newContract.start_date" name="start" required class="input"/>
                </div>
              </div>
              @if (contracts().length) {
                <p class="text-xs text-slate-400">Le contrat en cours sera clos automatiquement la veille de cette date.</p>
              }
              <div class="flex justify-end">
                <button type="submit" class="btn btn-primary">Enregistrer le contrat</button>
              </div>
            </form>
          }
        }

        <!-- ========== PRIMES & RETENUES ========== -->
        @if (tab() === 'adjustments') {
          <div class="overflow-x-auto mt-4"><table class="data-table">
            <thead>
              <tr><th>Période</th><th>Libellé</th><th class="num">Montant (FCFA)</th><th></th></tr>
            </thead>
            <tbody>
              @for (a of adjustments(); track a.id) {
                <tr>
                  <td class="px-4 py-3">{{ monthLabel(a.month) }} {{ a.year }}</td>
                  <td class="px-4 py-3">{{ a.description }}</td>
                  <td class="px-4 py-3 num" [class.text-rose-600]="a.amount < 0">{{ a.amount | number:'1.0-0' }}</td>
                  <td class="px-4 py-3 text-right">
                    @if (canEdit) {
                      <button (click)="deleteAdjustment(a)" class="btn btn-icon btn-secondary" title="Supprimer" aria-label="Supprimer"><app-icon name="trash"/></button>
                    }
                  </td>
                </tr>
              } @empty {
                <tr><td colspan="4" class="px-4 py-6 text-center text-slate-400">Aucune prime ni retenue.</td></tr>
              }
            </tbody>
          </table></div>

          @if (canEdit) {
            <form (ngSubmit)="createAdjustment()" class="card p-4 mt-4 space-y-3">
              <h3 class="card-title">Ajouter une prime ou une retenue</h3>
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div>
                  <label class="label">Mois</label>
                  <select [(ngModel)]="newAdj.month" name="adjMonth" class="select">
                    @for (m of months; track $index) { <option [ngValue]="$index + 1">{{ m }}</option> }
                  </select>
                </div>
                <div>
                  <label class="label">Année</label>
                  <input type="number" [(ngModel)]="newAdj.year" name="adjYear" class="input"/>
                </div>
                <div>
                  <label class="label">Type</label>
                  <select [(ngModel)]="adjKind" name="adjKind" class="select">
                    <option value="prime">Prime (+)</option>
                    <option value="retenue">Retenue (−)</option>
                  </select>
                </div>
                <div>
                  <label class="label">Montant (FCFA)</label>
                  <input type="number" min="1" [(ngModel)]="adjAmount" name="adjAmount" required class="input"/>
                </div>
              </div>
              <div>
                <label class="label">Libellé</label>
                <input type="text" [(ngModel)]="newAdj.description" name="adjDesc" required class="input" placeholder="Prime de rendement, avance sur salaire…"/>
              </div>
              <div class="flex justify-end">
                <button type="submit" class="btn btn-primary">Ajouter</button>
              </div>
            </form>
          }
        }

        <!-- ========== HEURES ========== -->
        @if (tab() === 'timesheets') {
          <div class="overflow-x-auto mt-4"><table class="data-table">
            <thead>
              <tr><th>Période</th><th class="num">Heures travaillées</th><th class="num">Heures sup.</th><th></th></tr>
            </thead>
            <tbody>
              @for (t of timesheets(); track t.id) {
                <tr>
                  <td class="px-4 py-3">{{ monthLabel(t.month) }} {{ t.year }}</td>
                  <td class="px-4 py-3 num">{{ t.hours_worked }}</td>
                  <td class="px-4 py-3 num">{{ t.overtime_h }}</td>
                  <td class="px-4 py-3 text-right">
                    @if (canEdit) {
                      <button (click)="editTimesheet(t)" class="btn btn-icon btn-secondary" title="Modifier" aria-label="Modifier"><app-icon name="edit"/></button>
                      <button (click)="deleteTimesheet(t)" class="btn btn-icon btn-secondary ml-1.5" title="Supprimer" aria-label="Supprimer"><app-icon name="trash"/></button>
                    }
                  </td>
                </tr>
              } @empty {
                <tr><td colspan="4" class="px-4 py-6 text-center text-slate-400">Aucun relevé d'heures.</td></tr>
              }
            </tbody>
          </table></div>

          @if (canEdit) {
            <form (ngSubmit)="saveTimesheet()" class="card p-4 mt-4 space-y-3">
              <h3 class="card-title">Saisir le relevé d'un mois</h3>
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div>
                  <label class="label">Mois</label>
                  <select [(ngModel)]="newTs.month" name="tsMonth" class="select">
                    @for (m of months; track $index) { <option [ngValue]="$index + 1">{{ m }}</option> }
                  </select>
                </div>
                <div>
                  <label class="label">Année</label>
                  <input type="number" [(ngModel)]="newTs.year" name="tsYear" class="input"/>
                </div>
                <div>
                  <label class="label">Heures travaillées</label>
                  <input type="number" min="0" step="0.5" [(ngModel)]="newTs.hours_worked" name="tsHours" class="input"/>
                </div>
                <div>
                  <label class="label">Heures sup.</label>
                  <input type="number" min="0" step="0.5" [(ngModel)]="newTs.overtime_h" name="tsOver" class="input"/>
                </div>
              </div>
              <p class="text-xs text-slate-400">Un seul relevé par mois : une nouvelle saisie remplace la précédente. Les heures servent notamment à la DISA des salariés horaires.</p>
              <div class="flex justify-end">
                <button type="submit" class="btn btn-primary">Enregistrer</button>
              </div>
            </form>
          }
        }
      </div>
    </div>
  `
})
export class EmployeeFileComponent implements OnInit {
    private api = inject(ApiService);

    @Input({ required: true }) employee!: Employee;
    @Input() canEdit = false;
    @Output() closed = new EventEmitter<void>();

    months = MONTHS;
    tab = signal<Tab>('contracts');
    error = signal('');
    success = signal('');

    contracts = signal<Contract[]>([]);
    adjustments = signal<Adjustment[]>([]);
    timesheets = signal<Timesheet[]>([]);

    closingId = signal<number | null>(null);
    closingDate = '';

    private now = new Date();
    newContract = { base_salary: 0, hourly_rate: 0, start_date: '' };
    newAdj = { month: this.now.getMonth() + 1, year: this.now.getFullYear(), description: '' };
    adjKind: 'prime' | 'retenue' = 'prime';
    adjAmount = 0;
    newTs = { month: this.now.getMonth() + 1, year: this.now.getFullYear(), hours_worked: 173.33, overtime_h: 0 };

    ngOnInit(): void {
        this.loadAll();
    }

    private loadAll(): void {
        this.api.getEmployeeContracts(this.employee.id).subscribe({ next: (c) => this.contracts.set(c), error: (e) => this.fail(e) });
        this.api.getAdjustments(this.employee.id).subscribe({
            next: (a) => this.adjustments.set([...a].sort((x, y) => (y.year * 12 + y.month) - (x.year * 12 + x.month))),
            error: (e) => this.fail(e)
        });
        this.api.getTimesheets(this.employee.id).subscribe({ next: (t) => this.timesheets.set(t), error: (e) => this.fail(e) });
    }

    private fail(e: HttpErrorResponse): void {
        this.success.set('');
        this.error.set(e?.error?.error || e?.error?.message || 'Opération impossible.');
    }

    private done(message: string): void {
        this.error.set('');
        this.success.set(message);
        this.loadAll();
    }

    day(iso: string): string {
        return iso ? iso.slice(0, 10).split('-').reverse().join('/') : '—';
    }

    monthLabel(m: number): string {
        return MONTHS[m - 1] || `${m}`;
    }

    isOpen(c: Contract): boolean {
        return !c.end_date || new Date(c.end_date) >= new Date(new Date().toDateString());
    }

    createContract(): void {
        if (!this.newContract.base_salary || !this.newContract.start_date) {
            this.error.set('Salaire de base et date de début sont obligatoires.');
            return;
        }
        this.api.createContract({
            employee_id: this.employee.id,
            base_salary: Number(this.newContract.base_salary),
            hourly_rate: Number(this.newContract.hourly_rate) || 0,
            start_date: `${this.newContract.start_date}T00:00:00Z`,
            currency: 'XOF'
        }).subscribe({
            next: () => {
                this.newContract = { base_salary: 0, hourly_rate: 0, start_date: '' };
                this.done('Contrat enregistré.');
            },
            error: (e) => this.fail(e)
        });
    }

    endContract(c: Contract): void {
        if (!this.closingDate) {
            this.error.set('Choisissez la date de fin du contrat.');
            return;
        }
        this.api.endContract(c.id, this.closingDate).subscribe({
            next: (r) => {
                this.closingId.set(null);
                this.done(r.message);
            },
            error: (e) => this.fail(e)
        });
    }

    createAdjustment(): void {
        const amount = Math.abs(Number(this.adjAmount));
        if (!amount || !this.newAdj.description.trim()) {
            this.error.set('Montant et libellé sont obligatoires.');
            return;
        }
        this.api.createAdjustment({
            employee_id: this.employee.id,
            month: this.newAdj.month,
            year: Number(this.newAdj.year),
            amount: this.adjKind === 'retenue' ? -amount : amount,
            description: this.newAdj.description.trim()
        }).subscribe({
            next: () => {
                this.adjAmount = 0;
                this.newAdj.description = '';
                this.done('Élément de paie ajouté. Recalculez le bulletin du mois s\'il est déjà généré.');
            },
            error: (e) => this.fail(e)
        });
    }

    deleteAdjustment(a: Adjustment): void {
        if (!window.confirm(`Supprimer « ${a.description} » (${a.amount} FCFA) ?`)) return;
        this.api.deleteAdjustment(a.id).subscribe({ next: () => this.done('Élément supprimé.'), error: (e) => this.fail(e) });
    }

    editTimesheet(t: Timesheet): void {
        this.newTs = { month: t.month, year: t.year, hours_worked: t.hours_worked, overtime_h: t.overtime_h };
    }

    saveTimesheet(): void {
        this.api.saveTimesheet({
            employee_id: this.employee.id,
            month: this.newTs.month,
            year: Number(this.newTs.year),
            hours_worked: Number(this.newTs.hours_worked) || 0,
            overtime_h: Number(this.newTs.overtime_h) || 0
        }).subscribe({ next: (r) => this.done(r.message), error: (e) => this.fail(e) });
    }

    deleteTimesheet(t: Timesheet): void {
        if (!window.confirm(`Supprimer le relevé de ${this.monthLabel(t.month)} ${t.year} ?`)) return;
        this.api.deleteTimesheet(t.id).subscribe({ next: () => this.done('Relevé supprimé.'), error: (e) => this.fail(e) });
    }
}
