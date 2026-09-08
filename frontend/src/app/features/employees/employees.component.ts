import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { Employee } from '../../core/models/kpay.models';

@Component({
    selector: 'app-employees',
    standalone: true,
    imports: [FormsModule],
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
        <button (click)="openModal()" class="btn btn-primary">
          + Nouvel Employé
        </button>
      </div>

      <!-- Tableau des Employés -->
      <div class="card overflow-hidden">
        <table class="data-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Nom & Prénom</th>
              <th>Email</th>
              <th>Manager (N+1)</th>
              <th>Parts Fiscales</th>
              <th>Statut</th>
            </tr>
          </thead>
          <tbody>
            @for (emp of employees(); track emp.id) {
              <tr>
                <td class="px-4 py-3.5 font-mono text-xs text-slate-400">#{{ emp.id }}</td>
                <td class="px-4 py-3.5 font-medium text-slate-900">{{ emp.last_name }} {{ emp.first_name }}</td>
                <td class="px-4 py-3.5 text-slate-500">{{ emp.email }}</td>
                <td class="px-4 py-3.5 text-slate-500">{{ managerName(emp.manager_id) }}</td>
                <td class="px-4 py-3.5">{{ emp.tax_parts }}</td>
                <td class="px-4 py-3.5">
                  <span [class]="emp.is_active ? 'badge badge-emerald' : 'badge badge-slate'">
                    {{ emp.is_active ? 'Actif' : 'Inactif' }}
                  </span>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="6" class="px-4 py-8 text-center text-slate-400">
                  Aucun employé enregistré pour le moment.
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <!-- Modale de Création -->
      @if (showModal()) {
        <div class="modal-overlay">
          <div class="modal">
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">Ajouter un Employé</h2>
            <form (ngSubmit)="saveEmployee()" class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
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
              <div class="grid grid-cols-2 gap-4">
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

    employees = signal<Employee[]>([]);
    employeesById = signal<Map<number, string>>(new Map());
    showModal = signal(false);
    errorMessage = signal('');

    newEmployee: Partial<Employee> = {
        first_name: '',
        last_name: '',
        email: '',
        tax_parts: 1.0,
        manager_id: null as unknown as number,
        is_active: true
    };

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
        this.showModal.set(true);
    }

    closeModal(): void {
        this.showModal.set(false);
    }

    saveEmployee(): void {
        if (!this.newEmployee.first_name || !this.newEmployee.last_name) return;

        this.apiService.createEmployee(this.newEmployee).subscribe({
            next: (emp) => {
                this.employees.update((list) => [...list, emp]);
                this.closeModal();
            },
            error: () => {
                this.errorMessage.set('Erreur lors de la création de l\'employé. Vérifiez vos informations.');
            }
        });
    }
}
