import { Component, inject, OnInit, signal } from '@angular/core';
import { NgClass } from '@angular/common';
import { ApiService } from '../../core/services/api.service';

@Component({
    selector: 'app-admin-roles',
    standalone: true,
    template: `
    <div class="space-y-6 max-w-4xl">
      <div class="page-head">
        <div>
          <h1 class="page-title">Rôles &amp; permissions</h1>
          <p class="page-subtitle">Contrôle d'accès granulaire (RBAC). Le rôle Admin conserve toutes les permissions de façon implicite.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      <div class="card overflow-hidden">
        <div class="flex border-b border-slate-200 overflow-x-auto">
          @for (role of roles(); track role.role) {
            <button
              (click)="selectRole(role.role)"
              class="px-5 py-3 text-sm font-medium whitespace-nowrap border-b-2 transition-colors"
              [ngClass]="selectedRole() === role.role ? 'border-blue-600 text-blue-700 bg-blue-50/50' : 'border-transparent text-slate-500 hover:text-slate-700'"
            >
              {{ roleLabel(role.role) }}
              @if (role.role === 'admin') {
                <span class="ml-1.5 text-[10px] uppercase tracking-wide text-slate-400">implicite</span>
              }
            </button>
          }
        </div>

        @if (selectedRole() && selectedRole() !== 'admin') {
          <div class="p-6">
            @for (module of modules(); track module) {
              <div class="mb-5">
                <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">{{ moduleLabel(module) }}</h3>
                <div class="grid sm:grid-cols-2 gap-2">
                  @for (perm of permissionsByModule(module); track perm.code) {
                    <label class="flex items-start gap-3 rounded-lg border border-slate-200 p-3 cursor-pointer hover:bg-slate-50 transition-colors">
                      <input
                        type="checkbox"
                        class="mt-0.5 w-4 h-4 accent-blue-600"
                        [checked]="selectedPermissions().includes(perm.code)"
                        (change)="togglePermission(perm.code)"
                      />
                      <span>
                        <span class="block text-sm font-medium text-slate-700">{{ perm.label }}</span>
                        <span class="block font-mono text-xs text-slate-400 mt-0.5">{{ perm.code }}</span>
                      </span>
                    </label>
                  }
                </div>
              </div>
            }

            <div class="pt-3 border-t border-slate-200 flex items-center gap-3">
              <button (click)="save()" class="btn btn-primary" [disabled]="saving()">
                {{ saving() ? 'Enregistrement…' : 'Enregistrer les permissions' }}
              </button>
              <button (click)="reloadSelected()" class="btn btn-secondary">Annuler</button>
              <span class="text-xs text-slate-400">{{ selectedPermissions().length }} permission(s)</span>
            </div>
          </div>
        }

        @if (selectedRole() === 'admin') {
          <div class="p-8 text-center text-sm text-slate-400">
            Le rôle <strong class="text-slate-600">Admin</strong> possède toutes les permissions ({{ allPermissionCount() }} codes) de façon implicite et ne peut pas être restreint.
          </div>
        }
      </div>
    </div>
  `,
    imports: [NgClass]
})
export class AdminRolesComponent implements OnInit {
    api = inject(ApiService);

    roles = signal<{ role: string; permissions: string[]; builtin: boolean }[]>([]);
    permissions = signal<{ code: string; label: string; module_name: string }[]>([]);
    selectedRole = signal('');
    selectedPermissions = signal<string[]>([]);
    saving = signal(false);
    errorMessage = signal('');
    successMessage = signal('');

    ngOnInit() {
        this.load();
    }

    load() {
        this.errorMessage.set('');
        this.api.getRoles().subscribe({
            next: (roles) => {
                this.roles.set(roles);
                if (roles.length > 0 && !this.selectedRole()) {
                    this.selectRole(roles[0].role);
                }
            },
            error: () => this.errorMessage.set('Impossible de charger les rôles.')
        });
        this.api.getPermissions().subscribe({
            next: (perms) => this.permissions.set(perms),
            error: () => this.errorMessage.set('Impossible de charger les permissions.')
        });
    }

    selectRole(role: string) {
        this.selectedRole.set(role);
        this.selectedPermissions.set(this.roles().find(r => r.role === role)?.permissions ?? []);
        this.successMessage.set('');
    }

    reloadSelected() {
        this.selectRole(this.selectedRole());
    }

    modules(): string[] {
        const set = Array.from(new Set(this.permissions().map(p => p.module_name)));
        return set;
    }

    permissionsByModule(module: string) {
        return this.permissions().filter(p => p.module_name === module);
    }

    togglePermission(code: string) {
        const current = this.selectedPermissions();
        this.selectedPermissions.set(current.includes(code) ? current.filter(c => c !== code) : [...current, code]);
    }

    save() {
        const role = this.selectedRole();
        if (!role || role === 'admin') return;
        this.saving.set(true);
        this.errorMessage.set('');
        this.successMessage.set('');
        this.api.updateRolePermissions(role, this.selectedPermissions()).subscribe({
            next: (res) => {
                this.saving.set(false);
                if (res.success) {
                    this.successMessage.set(res.message || 'Permissions mises à jour.');
                    this.load();
                } else {
                    this.errorMessage.set(res.message || 'Échec de la mise à jour.');
                }
            },
            error: (err) => {
                this.saving.set(false);
                this.errorMessage.set(err?.error?.error || err?.error?.message || 'Erreur lors de la mise à jour.');
            }
        });
    }

    roleLabel(role: string): string {
        const labels: Record<string, string> = {
            admin: 'Admin',
            payroll_officer: 'Gestionnaire RH',
            accountant: 'Comptable',
            manager: 'Manager',
            employee: 'Employé'
        };
        return labels[role] ?? role;
    }

    moduleLabel(module: string): string {
        const labels: Record<string, string> = {
            general: 'Général',
            hr: 'Ressources humaines',
            payroll: 'Paie',
            leave: 'Congés & absences',
            tax: 'Règles sociales',
            admin: 'Administration'
        };
        return labels[module] ?? module;
    }

    allPermissionCount(): number {
        return this.permissions().length;
    }
}