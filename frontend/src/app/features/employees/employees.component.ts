import { Component, inject, OnInit, signal } from '@angular/core';
import { IconComponent } from '../../shared/icon.component';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { Employee } from '../../core/models/kpay.models';
import { EmployeeFileComponent } from './employee-file.component';

@Component({
    selector: 'app-employees',
    standalone: true,
    imports: [FormsModule, EmployeeFileComponent, IconComponent],
    template: `
    <div class="space-y-6">
      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      <div class="page-head">
        <div>
          <h1 class="page-title">Gestion des Employés</h1>
          <p class="page-subtitle">Consultez et gérez les fiches des salariés de l'organisation.</p>
        </div>
        @if (canCreateEmployee()) {
          <button (click)="openModal()" class="btn btn-primary">
            + Nouvel Employé
          </button>
        }
      </div>

      <!-- Tableau des Employés -->
      <!-- Colonnes secondaires masquées selon la largeur ; l'email et le statut
           passent sous le nom quand leur colonne est masquée -->
      <div class="card overflow-x-auto">
        <table class="data-table">
          <thead>
            <tr>
              <th class="hidden md:table-cell">ID</th>
              <th>Nom & Prénom</th>
              <th class="hidden xl:table-cell">Email</th>
              <th class="hidden md:table-cell">N° CNPS</th>
              <th class="hidden 2xl:table-cell">Manager (N+1)</th>
              <th class="hidden 2xl:table-cell">Parts Fiscales</th>
              <th class="hidden sm:table-cell">Statut</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            @for (emp of employees(); track emp.id) {
              <tr>
                <td class="hidden md:table-cell px-4 py-3.5 font-mono text-xs text-slate-400">#{{ emp.id }}</td>
                <td class="px-4 py-3.5">
                  <div class="font-medium text-slate-900">{{ emp.last_name }} {{ emp.first_name }}</div>
                  <div class="xl:hidden text-xs text-slate-500 break-all">{{ emp.email }}</div>
                  <div class="sm:hidden mt-1">
                    <span [class]="emp.is_active ? 'badge badge-emerald' : 'badge badge-slate'">{{ emp.is_active ? 'Actif' : 'Inactif' }}</span>
                  </div>
                </td>
                <td class="hidden xl:table-cell px-4 py-3.5 text-slate-500">{{ emp.email }}</td>
                <td class="hidden md:table-cell px-4 py-3.5 font-mono text-xs">
                  @if (emp.cnps_number) { {{ emp.cnps_number }} } @else { <span class="badge badge-amber">À renseigner</span> }
                </td>
                <td class="hidden 2xl:table-cell px-4 py-3.5 text-slate-500">{{ managerName(emp.manager_id) }}</td>
                <td class="hidden 2xl:table-cell px-4 py-3.5">{{ emp.tax_parts }}</td>
                <td class="hidden sm:table-cell px-4 py-3.5">
                  <span [class]="emp.is_active ? 'badge badge-emerald' : 'badge badge-slate'">
                    {{ emp.is_active ? 'Actif' : 'Inactif' }}
                  </span>
                </td>
                <td class="px-4 py-3.5">
                  <div class="flex gap-1.5 justify-end">
                    <button (click)="fileOf.set(emp)" class="btn btn-icon btn-secondary" title="Dossier (contrats, primes, heures)" aria-label="Dossier (contrats, primes, heures)"><app-icon name="folder"/></button>
                    @if (canCreateEmployee()) {
                      <button (click)="openEdit(emp)" class="btn btn-icon btn-secondary" title="Modifier la fiche" aria-label="Modifier la fiche"><app-icon name="edit"/></button>
                    }
                  </div>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="8" class="px-4 py-8 text-center text-slate-400">
                  Aucun employé enregistré pour le moment.
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      @if (fileOf(); as f) {
        <app-employee-file [employee]="f" [canEdit]="canCreateEmployee()" (closed)="fileOf.set(null)"/>
      }

      <!-- Modale de Création -->
      @if (showModal()) {
        <div class="modal-overlay">
          <div class="modal">
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">{{ editingId() ? 'Modifier l\'employé' : 'Ajouter un Employé' }}</h2>
            <form (ngSubmit)="saveEmployee()" class="space-y-4">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="label">Nom</label>
                  <input type="text" [(ngModel)]="newEmployee.last_name" name="lastName" required class="input"/>
                </div>
                <div>
                  <label class="label">Prénom</label>
                  <input type="text" [(ngModel)]="newEmployee.first_name" name="firstName" required class="input"/>
                </div>
              </div>
              <div>
                <label class="label">Email Professionnel</label>
                <input type="email" [(ngModel)]="newEmployee.email" name="email" required class="input"/>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="label">Téléphone</label>
                  <input type="tel" [(ngModel)]="newEmployee.phone" name="phone" class="input" placeholder="+225 07 00 00 00 00"/>
                </div>
                <div>
                  <label class="label">Adresse</label>
                  <input type="text" [(ngModel)]="newEmployee.address" name="address" class="input" placeholder="Cocody, Abidjan"/>
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="label">IBAN</label>
                  <input type="text" [(ngModel)]="newEmployee.iban" name="iban" class="input" placeholder="CI93 0100 0100 1234 5678 9012 34"/>
                </div>
                <div>
                  <label class="label">BIC (banque)</label>
                  <input type="text" [(ngModel)]="newEmployee.bic" name="bic" class="input" placeholder="BNFACIXX"/>
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label class="label">Parts Fiscales (IGR)</label>
                  <input type="number" step="0.5" [(ngModel)]="newEmployee.tax_parts" name="taxParts" required class="input"/>
                </div>
                <div>
                  <label class="label">Manager (N+1)</label>
                  <select [(ngModel)]="newEmployee.manager_id" name="manager" class="select">
                    <option [ngValue]="null">— Aucun (décision RH directe) —</option>
                    @for (e of employees(); track e.id) {
                      <option [ngValue]="e.id">{{ e.last_name }} {{ e.first_name }}</option>
                    }
                  </select>
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label class="label">N° CNPS</label>
                  <input type="text" [(ngModel)]="newEmployee.cnps_number" name="cnps" class="input font-mono" placeholder="12 chiffres" maxlength="16"/>
                </div>
                <div>
                  <label class="label">Date de naissance</label>
                  <input type="date" [(ngModel)]="newEmployee.birth_date" name="birthDate" class="input"/>
                </div>
                <div>
                  <label class="label">Périodicité du salaire</label>
                  <select [(ngModel)]="newEmployee.salary_type" name="salaryType" class="select">
                    <option value="M">Mensuel</option>
                    <option value="H">Horaire</option>
                    <option value="J">Journalier</option>
                  </select>
                </div>
              </div>
              <p class="text-xs text-slate-400 -mt-2">N° CNPS, date de naissance et périodicité sont requis pour la DISA annuelle.</p>
              @if (formError()) {
                <div class="alert alert-error">{{ formError() }}</div>
              }
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="closeModal()" class="btn btn-secondary">Annuler</button>
                <button type="submit" class="btn btn-primary">Enregistrer</button>
              </div>
            </form>
          </div>
        </div>
      }
    </div>
  `
})
export class EmployeesComponent implements OnInit {
    private apiService = inject(ApiService);
    private authService = inject(AuthService);

    employees = signal<Employee[]>([]);
    employeesById = signal<Map<number, string>>(new Map());
    showModal = signal(false);
    editingId = signal<number | null>(null);
    fileOf = signal<Employee | null>(null);
    errorMessage = signal('');
    formError = signal('');

    canCreateEmployee(): boolean {
        const role = this.authService.currentUser()?.role || '';
        return role === 'admin' || role === 'payroll_officer';
    }

    newEmployee: Partial<Employee> = this.emptyEmployee();

    private emptyEmployee(): Partial<Employee> {
        return {
        first_name: '',
        last_name: '',
        email: '',
        phone: '',
        address: '',
        iban: '',
        bic: '',
        tax_parts: 1.0,
        manager_id: null as unknown as number,
        is_active: true,
        cnps_number: '',
        birth_date: '',
        salary_type: 'M'
        };
    }

    ngOnInit(): void {
        this.loadEmployees();
    }

    loadEmployees(): void {
        this.apiService.getEmployees().subscribe({
            next: (data) => {
                this.employees.set(data);
                const map = new Map<number, string>();
                for (const e of data) map.set(e.id, `${e.last_name} ${e.first_name}`);
                this.employeesById.set(map);
            },
            error: () => {
                this.employees.set([]);
                this.employeesById.set(new Map());
            }
        });
    }

    managerName(manager_id?: number): string {
        if (!manager_id) return '—';
        return this.employeesById().get(manager_id) || `Manager #${manager_id}`;
    }

    openModal(): void {
        this.editingId.set(null);
        this.newEmployee = this.emptyEmployee();
        this.formError.set('');
        this.showModal.set(true);
    }

    openEdit(emp: Employee): void {
        this.editingId.set(emp.id);
        this.newEmployee = {
            ...emp,
            manager_id: emp.manager_id ?? (null as unknown as number),
            salary_type: emp.salary_type || 'M'
        };
        this.formError.set('');
        this.showModal.set(true);
    }

    closeModal(): void {
        this.showModal.set(false);
        this.editingId.set(null);
    }

    saveEmployee(): void {
        if (!this.newEmployee.first_name || !this.newEmployee.last_name) return;

        const id = this.editingId();
        const payload: Partial<Employee> = { ...this.newEmployee, manager_id: this.newEmployee.manager_id || (null as unknown as number) };
        const request$: Observable<unknown> = id
            ? this.apiService.updateEmployee(id, payload)
            : this.apiService.createEmployee(payload);
        request$.subscribe({
            next: () => {
                this.closeModal();
                this.loadEmployees();
            },
            error: (err: HttpErrorResponse) => {
                this.formError.set(err?.error?.error || err?.error?.message || 'Erreur lors de l\'enregistrement. Vérifiez vos informations.');
            }
        });
    }
}
