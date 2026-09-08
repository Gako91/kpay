import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { Employee, LeaveBalance, LeaveRequest } from '../../core/models/kpay.models';

@Component({
    selector: 'app-leaves',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6">
      <div class="page-head">
        <div>
          <h1 class="page-title">Congés & Absences</h1>
          <p class="page-subtitle">Workflow à 2 niveaux (N+1 → RH), soldes annuels et congé maladie avec justificatif.</p>
        </div>
        <button (click)="showModal.set(true)" class="btn btn-primary">
          + Nouvelle Demande
        </button>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      <!-- Soldes annuels -->
      @if (me()) {
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          @for (b of balances(); track b.leave_type) {
            <div class="kpi-card">
              <div class="kpi-label uppercase">{{ leaveTypeLabel(b.leave_type) }}</div>
              <div class="kpi-value">{{ balanceRemain(b) }} j</div>
              <div class="text-xs text-slate-400 mt-1">Acquis {{ b.accrued_days }} · Pris {{ b.used_days }}</div>
            </div>
          }
        </div>
      }

      <!-- Onglets -->
      @if (me() || canManage()) {
        <div class="flex gap-2">
          @if (me()) {
            <button (click)="tab.set('mes')" class="chip" [class]="tab() === 'mes' ? 'chip-active' : 'chip-idle'">
              Mes demandes
            </button>
          }
          @if (me()) {
            <button (click)="tab.set('equipe')" class="chip" [class]="tab() === 'equipe' ? 'chip-active' : 'chip-idle'">
              Mon équipe
            </button>
          }
          @if (canManage()) {
            <button (click)="tab.set('toutes')" class="chip" [class]="tab() === 'toutes' ? 'chip-active' : 'chip-idle'">
              Toutes les demandes
            </button>
          }
        </div>
      }

      <!-- Liste des demandes -->
      <div class="card overflow-hidden">
        <table class="data-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Employé</th>
              <th>Type</th>
              <th>Période</th>
              <th class="text-right">Jours</th>
              <th>Statut</th>
              <th>Motif / Refus</th>
              <th>Justificatif</th>
              <th class="text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            @for (r of visibleLeaves(); track r.id) {
              <tr>
                <td class="px-4 py-3.5 font-mono text-xs text-slate-400">#{{ r.id }}</td>
                <td class="px-4 py-3.5 font-medium text-slate-900">{{ employeeName(r.employee_id) }}</td>
                <td class="px-4 py-3.5">{{ leaveTypeLabel(r.leave_type) }}</td>
                <td class="px-4 py-3.5 whitespace-nowrap">{{ formatDate(r.start_date) }} → {{ formatDate(r.end_date) }}</td>
                <td class="px-4 py-3.5 num">{{ r.days_count }}</td>
                <td class="px-4 py-3.5">
                  <span [class]="statusClass(r.status)">
                    {{ statusLabel(r.status) }}
                  </span>
                </td>
                <td class="px-4 py-3.5 text-slate-500 max-w-[14rem] truncate" [title]="r.rejection_reason || r.reason">
                  {{ r.rejection_reason || r.reason || '—' }}
                </td>
                <td class="px-4 py-3.5">
                  @if (r.leave_type === 'maladie') {
                    @if (r.justificatif_path) {
                      <button (click)="downloadJustificatif(r.id)" class="text-xs font-medium text-blue-600 hover:underline">Voir PDF</button>
                    } @else {
                      <label class="text-xs font-medium text-slate-500 cursor-pointer hover:text-blue-600">
                        {{ isMine(r) ? 'Joindre' : '—' }}
                        <input type="file" accept="application/pdf" class="hidden" (change)="uploadJustificatif($event, r.id)"/>
                      </label>
                    }
                  } @else {
                    <span class="text-xs text-slate-300">—</span>
                  }
                </td>
                <td class="px-4 py-3.5">
                  <div class="flex gap-1.5 justify-end">
                    @if (r.status === 'en_attente' && canDecide(r, 'mgr')) {
                      <button (click)="mgrDecision(r.id, 'approve')" class="btn btn-sm btn-secondary">Valider N+1</button>
                      <button (click)="mgrDecision(r.id, 'reject')" class="btn btn-sm btn-danger">Refuser</button>
                    }
                    @if (r.status === 'valide_mgr' && canManage()) {
                      <button (click)="rhDecision(r.id, 'approve')" class="btn btn-sm btn-secondary">Approuver (RH)</button>
                      <button (click)="rhDecision(r.id, 'reject')" class="btn btn-sm btn-danger">Refuser (RH)</button>
                    }
                    @if (canManage() && r.status === 'en_attente') {
                      <button (click)="rhDecision(r.id, 'approve')" class="btn btn-sm btn-secondary" title="Décision RH directe (sans N+1)">Décider RH</button>
                    }
                    @if (r.status === 'approuve' || r.status === 'refuse') {
                      <span class="text-xs text-slate-400">{{ r.status === 'approuve' ? (r.approved_by || '') : (r.approved_by_mgr || r.approved_by || '') }}</span>
                    }
                  </div>
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="9" class="px-4 py-8 text-center text-slate-400">
                  Aucune demande de congé.
                </td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <!-- Modale de création -->
      @if (showModal()) {
        <div class="modal-overlay">
          <div class="modal">
            <h2 class="text-lg font-semibold text-slate-900 tracking-tight">Nouvelle Demande de Congé</h2>
            <form (ngSubmit)="createLeave()" class="space-y-4">
              @if (canManage()) {
                <div>
                  <label class="label">Employé</label>
                  <select [(ngModel)]="newLeave.employee_id" name="employee" required class="select">
                    <option [ngValue]="null" disabled>— Sélectionner —</option>
                    @for (e of employeeList(); track e.id) {
                      <option [ngValue]="e.id">{{ e.last_name }} {{ e.first_name }}</option>
                    }
                  </select>
                </div>
              } @else {
                <div class="text-sm text-slate-500">
                  Demandeur : <span class="font-medium text-slate-800">{{ me()?.last_name }} {{ me()?.first_name }}</span>
                </div>
              }
              <div>
                <label class="label">Type de congé</label>
                <select [(ngModel)]="newLeave.leave_type" name="leaveType" required class="select">
                  <option value="conge_paye">Congé payé</option>
                  <option value="rtt">RTT</option>
                  <option value="maladie">Maladie</option>
                  <option value="sans_solde">Sans solde</option>
                </select>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Date de début</label>
                  <input type="date" [(ngModel)]="newLeave.start_date" name="startDate" required class="input"/>
                </div>
                <div>
                  <label class="label">Date de fin</label>
                  <input type="date" [(ngModel)]="newLeave.end_date" name="endDate" required class="input"/>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="label">Nombre de jours</label>
                  <input type="number" step="0.5" min="0.5" [(ngModel)]="newLeave.days_count" name="days" required class="input"/>
                </div>
                <div>
                  <label class="label">Motif</label>
                  <input type="text" [(ngModel)]="newLeave.reason" name="reason" class="input"/>
                </div>
              </div>
              <div class="flex justify-end gap-3 pt-4 border-t border-slate-100">
                <button type="button" (click)="showModal.set(false)" class="btn btn-secondary">Annuler</button>
                <button type="submit" class="btn btn-primary">Soumettre</button>
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
    private auth = inject(AuthService);

    me = signal<Employee | null>(null);
    balances = signal<LeaveBalance[]>([]);
    myLeaves = signal<LeaveRequest[]>([]);
    teamLeaves = signal<LeaveRequest[]>([]);
    allLeaves = signal<LeaveRequest[]>([]);
    employees = signal<Map<number, string>>(new Map());
    employeeList = signal<Employee[]>([]);
    tab = signal<'mes' | 'equipe' | 'toutes'>('mes');
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

    get role(): string {
        return this.auth.currentUser()?.role || '';
    }

    canManage(): boolean {
        return this.role === 'admin' || this.role === 'payroll_officer';
    }

    ngOnInit(): void {
        this.loadEmployees();
        this.loadMe();
    }

    loadMe(): void {
        this.apiService.getMe().subscribe({
            next: (emp) => {
                this.me.set(emp);
                this.loadBalances();
                this.loadMyLeaves();
                this.loadTeamLeaves();
            },
            error: () => {
                this.me.set(null);
                if (this.canManage()) {
                    this.tab.set('toutes');
                    this.loadAllLeaves();
                }
            }
        });
    }

    loadBalances(): void {
        this.apiService.getMyLeaveBalance().subscribe({
            next: (b) => this.balances.set(b),
            error: () => this.balances.set([])
        });
    }

    loadMyLeaves(): void {
        this.apiService.getMyLeaveRequests().subscribe({
            next: (l) => this.myLeaves.set(l),
            error: () => this.myLeaves.set([])
        });
    }

    loadTeamLeaves(): void {
        this.apiService.getTeamLeaveRequests().subscribe({
            next: (l) => this.teamLeaves.set(l),
            error: () => this.teamLeaves.set([])
        });
    }

    loadAllLeaves(): void {
        this.apiService.getLeaveRequests().subscribe({
            next: (l) => this.allLeaves.set(l),
            error: () => this.allLeaves.set([])
        });
    }

    visibleLeaves(): LeaveRequest[] {
        if (this.tab() === 'mes') return this.myLeaves();
        if (this.tab() === 'equipe') return this.teamLeaves();
        return this.allLeaves();
    }

    refresh(): void {
        this.loadBalances();
        this.loadMyLeaves();
        this.loadTeamLeaves();
        if (this.canManage()) this.loadAllLeaves();
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

    createLeave(): void {
        const filled = this.canManage()
            ? (this.newLeave.employee_id && this.newLeave.start_date && this.newLeave.end_date && this.newLeave.leave_type)
            : (this.newLeave.start_date && this.newLeave.end_date && this.newLeave.leave_type);
        if (!filled) {
            this.errorMessage.set('Veuillez remplir tous les champs obligatoires.');
            return;
        }

        const done = () => {
            this.showModal.set(false);
            this.successMessage.set('Demande de congé soumise avec succès.');
            this.newLeave = { employee_id: null as unknown as number, leave_type: 'conge_paye', start_date: '', end_date: '', days_count: 1, reason: '' };
            this.refresh();
        };
        const fails = (err: any) => this.errorMessage.set(this.extractError(err) || 'Erreur lors de la création de la demande.');

        if (this.canManage()) {
            this.apiService.createLeaveRequest(this.newLeave).subscribe({ next: done, error: fails });
        } else {
            this.apiService.createMyLeaveRequest(this.newLeave).subscribe({ next: done, error: fails });
        }
    }

    mgrDecision(id: number, action: 'approve' | 'reject'): void {
        if (action === 'reject') {
            const reason = window.prompt('Motif du refus (N+1) :');
            if (reason === null) return;
            this.apiService.mgrRejectLeave(id, reason).subscribe({ next: () => this.afterDecision('Demande refusée (N+1)'), error: (e) => this.errorMessage.set(this.extractError(e)) });
            return;
        }
        this.apiService.mgrApproveLeave(id).subscribe({ next: () => this.afterDecision('Demande validée par le N+1'), error: (e) => this.errorMessage.set(this.extractError(e)) });
    }

    rhDecision(id: number, action: 'approve' | 'reject'): void {
        if (action === 'reject') {
            const reason = window.prompt('Motif du refus (RH) :');
            if (reason === null) return;
            this.apiService.rhRejectLeave(id, reason).subscribe({ next: () => this.afterDecision('Demande refusée (RH)'), error: (e) => this.errorMessage.set(this.extractError(e)) });
            return;
        }
        this.apiService.rhApproveLeave(id).subscribe({ next: () => this.afterDecision('Demande approuvée (RH) — solde débité'), error: (e) => this.errorMessage.set(this.extractError(e)) });
    }

    afterDecision(message: string): void {
        this.successMessage.set(message);
        this.refresh();
    }

    canDecide(r: LeaveRequest, level: 'mgr' | 'rh'): boolean {
        if (this.canManage()) return true;
        if (level === 'mgr') return this.me()?.id === this.managerOf(r.employee_id);
        return false;
    }

    managerOf(employeeId: number): number | undefined {
        const emp = this.employeeList().find((e) => e.id === employeeId);
        return emp?.manager_id;
    }

    isMine(r: LeaveRequest): boolean {
        return this.me()?.id === r.employee_id;
    }

    uploadJustificatif(event: Event, leaveId: number): void {
        const input = event.target as HTMLInputElement;
        if (!input.files?.length) return;
        const file = input.files[0];
        if (file.size > 1_048_576) {
            this.errorMessage.set('Fichier trop volumineux (maximum 1 Mo).');
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const b64 = String(reader.result).split(',')[1] || '';
            this.apiService.uploadLeaveJustificatif(leaveId, b64, file.name).subscribe({
                next: () => this.afterDecision('Justificatif enregistré.'),
                error: (e) => this.errorMessage.set(this.extractError(e))
            });
        };
        reader.readAsDataURL(file);
    }

    downloadJustificatif(leaveId: number): void {
        this.apiService.downloadLeaveJustificatif(leaveId).subscribe({
            next: (blob) => {
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `justificatif_${leaveId}.pdf`;
                a.click();
                URL.revokeObjectURL(url);
            },
            error: (e) => this.errorMessage.set(this.extractError(e))
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

    balanceRemain(b: LeaveBalance): number {
        return b.accrued_days - b.used_days;
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
            en_attente: 'En attente N+1',
            valide_mgr: 'Validé N+1 · RH',
            approuve: 'Approuvé',
            refuse: 'Refusé'
        };
        return labels[status] || status;
    }

    statusClass(status: string): string {
        const classes: Record<string, string> = {
            en_attente: 'badge badge-amber',
            valide_mgr: 'badge badge-blue',
            approuve: 'badge badge-emerald',
            refuse: 'badge badge-rose'
        };
        return classes[status] || 'badge badge-slate';
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