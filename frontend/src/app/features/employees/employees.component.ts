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
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">{{ errorMessage() }}</div>
      }
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Gestion des Employés</h1>
          <p class="text-slate-500 text-sm">Consultez et gérez les fiches des salariés de l'organisation.</p>
        </div>
        <button (click)="openModal()" class="bg-blue-600 hover:bg-blue-700 text-white font-medium px-4 py-2.5 rounded-lg text-sm transition shadow">
          + Nouvel Employé
        </button>
      </div>

      <!-- Tableau des Employés -->
      <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <table class="w-full text-left text-sm text-slate-600">
          <thead class="bg-slate-50 text-slate-700 uppercase font-semibold text-xs border-b border-slate-200">
            <tr>
              <th class="px-6 py-3.5">ID</th>
              <th class="px-6 py-3.5">Nom & Prénom</th>
              <th class="px-6 py-3.5">Email</th>
              <th class="px-6 py-3.5">Parts Fiscales</th>
              <th class="px-6 py-3.5">Statut</th>
            </tr>
          </thead>
          <tbody class="divide-y border-slate-100">
            @for (emp of employees(); track emp.id) {
              <tr class="hover:bg-slate-50 transition">
                <td class="px-6 py-4 font-mono text-xs text-slate-400">#{{ emp.id }}</td>
                <td class="px-6 py-4 font-medium text-slate-900">{{ emp.last_name }} {{ emp.first_name }}</td>
                <td class="px-6 py-4 text-slate-500">{{ emp.email }}</td>
                <td class="px-6 py-4">{{ emp.tax_parts }}</td>
                <td class="px-6 py-4">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium" [class]="emp.is_active ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-100 text-slate-800'">
                    {{ emp.is_active ? 'Actif' : 'Inactif' }}
                  </span>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="5" class="px-6 py-8 text-center text-slate-400">
                  Aucun employé enregistré pour le moment.
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <!-- Modale de Création -->
      @if (showModal()) {
        <div class="fixed inset-0 bg-slate-900/50 flex items-center justify-center p-4 z-50">
          <div class="bg-white rounded-2xl p-6 w-full max-w-lg shadow-2xl space-y-4">
            <h2 class="text-xl font-bold text-slate-800">Ajouter un Employé</h2>
            <form (ngSubmit)="saveEmployee()" class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Nom</label>
                  <input type="text" [(ngModel)]="newEmployee.last_name" name="lastName" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm focus:ring-blue-500 focus:border-blue-500"/>
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Prénom</label>
                  <input type="text" [(ngModel)]="newEmployee.first_name" name="firstName" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm focus:ring-blue-500 focus:border-blue-500"/>
                </div>
              </div>
              <div>
                <label class="block text-xs font-medium text-slate-700 mb-1">Email Professionnel</label>
                <input type="email" [(ngModel)]="newEmployee.email" name="email" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm focus:ring-blue-500 focus:border-blue-500"/>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Parts Fiscales (IGR)</label>
                  <input type="number" step="0.5" [(ngModel)]="newEmployee.tax_parts" name="taxParts" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm focus:ring-blue-500 focus:border-blue-500"/>
                </div>
              </div>
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="closeModal()" class="px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 rounded-lg">Annuler</button>
                <button type="submit" class="px-4 py-2 text-sm font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg">Enregistrer</button>
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
    showModal = signal(false);
    errorMessage = signal('');

    newEmployee: Partial<Employee> = {
        first_name: '',
        last_name: '',
        email: '',
        tax_parts: 1.0,
        is_active: true
    };

    ngOnInit(): void {
        this.loadEmployees();
    }

    loadEmployees(): void {
        this.apiService.getEmployees().subscribe({
            next: (data) => this.employees.set(data),
            error: () => {
                this.employees.set([]);
            }
        });
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
