import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { Employee, LeaveRequest } from '../../core/models/kpay.models';

@Component({
    selector: 'app-leaves',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-800">Congés & Absences</h1>
          <p class="text-slate-500 text-sm">Soumettez et gérez les demandes de congé des employés.</p>
        </div>
        <button (click)="showModal.set(true)" class="bg-blue-600 hover:bg-blue-700 text-white font-medium px-4 py-2.5 rounded-lg text-sm transition shadow">
          + Nouvelle Demande
        </button>
      </div>

      @if (errorMessage()) {
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="bg-emerald-50 border border-emerald-200 text-emerald-700 px-4 py-3 rounded-lg text-sm">{{ successMessage() }}</div>
      }

      <!-- Liste des demandes -->
      <div class="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <table class="w-full text-left text-sm text-slate-600">
          <thead class="bg-slate-50 text-slate-700 uppercase font-semibold text-xs border-b border-slate-200">
            <tr>
              <th class="px-6 py-3.5">ID</th>
              <th class="px-6 py-3.5">Employé</th>
              <th class="px-6 py-3.5">Type</th>
              <th class="px-6 py-3.5">Début</th>
              <th class="px-6 py-3.5">Fin</th>
              <th class="px-6 py-3.5 text-right">Jours</th>
              <th class="px-6 py-3.5">Statut</th>
              <th class="px-6 py-3.5">Motif</th>
              <th class="px-6 py-3.5 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y border-slate-100">
            @for (r of leaves(); track r.id) {
              <tr class="hover:bg-slate-50 transition">
                <td class="px-6 py-4 font-mono text-xs text-slate-400">#{{ r.id }}</td>
                <td class="px-6 py-4 font-medium text-slate-900">{{ employeeName(r.employee_id) }}</td>
                <td class="px-6 py-4">{{ leaveTypeLabel(r.leave_type) }}</td>
                <td class="px-6 py-4">{{ formatDate(r.start_date) }}</td>
                <td class="px-6 py-4">{{ formatDate(r.end_date) }}</td>
                <td class="px-6 py-4 text-right">{{ r.days_count }}</td>
                <td class="px-6 py-4">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium" [class]="statusClass(r.status)">
                    {{ statusLabel(r.status) }}
                  </span>
                </td>
                <td class="px-6 py-4 text-slate-500 max-w-[12rem] truncate">{{ r.reason || '—' }}</td>
                <td class="px-6 py-4">
                  <div class="flex gap-2 justify-end">
                    @if (r.status === 'en_attente') {
                      <button (click)="setStatus(r.id, 'approuve')" class="px-3 py-1.5 text-xs font-medium bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg">Approuver</button>
                      <button (click)="setStatus(r.id, 'refuse')" class="px-3 py-1.5 text-xs font-medium bg-rose-600 hover:bg-rose-700 text-white rounded-lg">Refuser</button>
                    }
                  </div>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="9" class="px-6 py-8 text-center text-slate-400">
                  Aucune demande de congé.
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <!-- Modale de création -->
      @if (showModal()) {
        <div class="fixed inset-0 bg-slate-900/50 flex items-center justify-center p-4 z-50">
          <div class="bg-white rounded-2xl p-6 w-full max-w-lg shadow-2xl space-y-4">
            <h2 class="text-xl font-bold text-slate-800">Nouvelle Demande de Congé</h2>
            <form (ngSubmit)="createLeave()" class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-slate-700 mb-1">Employé</label>
                <select [(ngModel)]="newLeave.employee_id" name="employee" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm">
                  <option [ngValue]="null" disabled>— Sélectionner —</option>
                  @for (e of employeeList(); track e.id) {
                    <option [ngValue]="e.id">{{ e.last_name }} {{ e.first_name }}</option>
                  }
                </select>
              </div>
              <div>
                <label class="block text-xs font-medium text-slate-700 mb-1">Type de congé</label>
                <select [(ngModel)]="newLeave.leave_type" name="leaveType" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm">
                  <option value="conge_paye">Congé payé</option>
                  <option value="rtt">RTT</option>
                  <option value="maladie">Maladie</option>
                  <option value="sans_solde">Sans solde</option>
                </select>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Date de début</label>
                  <input type="date" [(ngModel)]="newLeave.start_date" name="startDate" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm"/>
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Date de fin</label>
                  <input type="date" [(ngModel)]="newLeave.end_date" name="endDate" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm"/>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Nombre de jours</label>
                  <input type="number" step="0.5" min="0.5" [(ngModel)]="newLeave.days_count" name="days" required class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm"/>
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Motif</label>
                  <input type="text" [(ngModel)]="newLeave.reason" name="reason" class="w-full px-3 py-2 rounded-lg border border-slate-300 text-sm"/>
                </div>
              </div>
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="showModal.set(false)" class="px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 rounded-lg">Annuler</button>
                <button type="submit" class="px-4 py-2 text-sm font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg">Soumettre</button>
              </div>
            </form>
          </div>
        </div>
      }
    </div>
  `
})
export class LeavesComponent implements OnInit {
    private apiService = inject(ApiService);

    leaves = signal<LeaveRequest[]>([]);
    employees = signal<Map<number, string>>(new Map());
    employeeList = signal<Employee[]>([]);
    showModal = signal(false);
    errorMessage = signal('');
    successMessage = signal('');

    newLeave: Partial<LeaveRequest> = {
        employee_id: null as unknown as number,
        leave_type: 'conge_paye',
        start_date: '',
        end_date: '',
        days_count: 1,
        reason: ''
    };

    ngOnInit(): void {
        this.loadEmployees();
        this.loadLeaves();
    }

    loadEmployees(): void {
        this.apiService.getEmployees().subscribe({
            next: (list) => {
                this.employeeList.set(list);
                const map = new Map<number, string>();
                for (const e of list) map.set(e.id, `${e.last_name} ${e.first_name}`);
                this.employees.set(map);
            },
            error: () => {
                this.employeeList.set([]);
                this.employees.set(new Map());
            }
        });
    }

    loadLeaves(): void {
        this.errorMessage.set('');
        this.successMessage.set('');
        this.apiService.getLeaveRequests().subscribe({
            next: (data) => this.leaves.set(data),
            error: (err) => {
                this.leaves.set([]);
                this.errorMessage.set(this.extractError(err) || 'Impossible de charger les demandes de congé.');
            }
        });
    }

    createLeave(): void {
        if (!this.newLeave.employee_id || !this.newLeave.start_date || !this.newLeave.end_date || !this.newLeave.leave_type) {
            this.errorMessage.set('Veuillez remplir tous les champs obligatoires.');
            return;
        }

        this.apiService.createLeaveRequest(this.newLeave).subscribe({
            next: () => {
                this.showModal.set(false);
                this.successMessage.set('Demande de congé soumise avec succès.');
                this.newLeave = { employee_id: null as unknown as number, leave_type: 'conge_paye', start_date: '', end_date: '', days_count: 1, reason: '' };
                this.loadLeaves();
            },
            error: (err) => this.errorMessage.set(this.extractError(err) || 'Erreur lors de la création de la demande.')
        });
    }

    setStatus(id: number, status: 'approuve' | 'refuse'): void {
        this.apiService.setLeaveStatus(id, status).subscribe({
            next: () => {
                this.successMessage.set(status === 'approuve' ? 'Demande approuvée.' : 'Demande refusée.');
                this.loadLeaves();
            },
            error: (err) => this.errorMessage.set(this.extractError(err) || 'Impossible de mettre à jour le statut.')
        });
    }

    employeeName(id: number): string {
        return this.employees().get(id) || `Employé #${id}`;
    }

    formatDate(dateStr: string): string {
        if (!dateStr) return '—';
        const d = new Date(dateStr);
        return d.toLocaleDateString('fr-FR');
    }

    leaveTypeLabel(type: string): string {
        const labels: Record<string, string> = {
            conge_paye: 'Congé payé',
            rtt: 'RTT',
            maladie: 'Maladie',
            sans_solde: 'Sans solde'
        };
        return labels[type] || type;
    }

    statusLabel(status: string): string {
        const labels: Record<string, string> = {
            en_attente: 'En attente',
            approuve: 'Approuvé',
            refuse: 'Refusé'
        };
        return labels[status] || status;
    }

    statusClass(status: string): string {
        const classes: Record<string, string> = {
            en_attente: 'bg-amber-100 text-amber-800',
            approuve: 'bg-emerald-100 text-emerald-800',
            refuse: 'bg-rose-100 text-rose-800'
        };
        return classes[status] || 'bg-slate-100 text-slate-800';
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