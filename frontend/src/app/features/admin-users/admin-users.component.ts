import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { User } from '../../core/models/kpay.models';

@Component({
    selector: 'app-admin-users',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6 max-w-5xl">
      <div class="page-head flex items-end justify-between gap-4">
        <div>
          <h1 class="page-title">Utilisateurs</h1>
          <p class="page-subtitle">Comptes KPay, rôles et activation. La création associe automatiquement l'employé correspondant (même email).</p>
        </div>
        <button (click)="showCreate.set(true)" class="btn btn-primary whitespace-nowrap">
          + Nouvel utilisateur
        </button>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      @if (showCreate()) {
        <div class="card p-6 space-y-4">
          <h2 class="font-semibold text-slate-800">Créer un compte</h2>
          <div class="grid sm:grid-cols-2 gap-4">
            <div>
              <label class="label">Nom d'utilisateur</label>
              <input type="text" [(ngModel)]="newUser.username" name="u_username" class="input" placeholder="ex: jdoe" />
            </div>
            <div>
              <label class="label">Email</label>
              <input type="email" [(ngModel)]="newUser.email" name="u_email" class="input" placeholder="ex: jdoe@vpro.ci" />
            </div>
            <div>
              <label class="label">Mot de passe</label>
              <input type="password" [(ngModel)]="newUser.password" name="u_password" class="input" placeholder="Min. 8 caractères" />
            </div>
            <div>
              <label class="label">Rôle</label>
              <select class="input" [(ngModel)]="newUser.role" name="u_role">
                <option value="">— Choisir —</option>
                <option value="payroll_officer">Gestionnaire RH</option>
                <option value="accountant">Comptable</option>
                <option value="manager">Manager</option>
                <option value="employee">Employé</option>
                <option value="admin">Admin</option>
              </select>
            </div>
          </div>
          <div class="flex gap-3">
            <button (click)="createUser()" class="btn btn-primary" [disabled]="creating()">
              {{ creating() ? 'Création…' : 'Créer le compte' }}
            </button>
            <button (click)="cancelCreate()" class="btn btn-secondary">Annuler</button>
          </div>
        </div>
      }

      <div class="data-table bg-white border border-slate-200 rounded-xl overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">Utilisateur</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">Email</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">Rôle</th>
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">Statut</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-slate-500">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            @for (user of users(); track user.id) {
              <tr class="hover:bg-slate-50/50">
                <td class="px-4 py-3 font-medium text-slate-700">{{ user.username }}</td>
                <td class="px-4 py-3 text-slate-500">{{ user.email }}</td>
                <td class="px-4 py-3">
                  <select
                    class="input px-2 py-1.5"
                    [disabled]="user.id === currentUserId()"
                    [ngModel]="user.role"
                    (ngModelChange)="changeRole(user, $event)"
                  >
                    <option value="payroll_officer">Gestionnaire RH</option>
                    <option value="accountant">Comptable</option>
                    <option value="manager">Manager</option>
                    <option value="employee">Employé</option>
                    <option value="admin">Admin</option>
                  </select>
                </td>
                <td class="px-4 py-3">
                  @if (user.is_active) {
                    <span class="badge badge-emerald">Actif</span>
                  } @else {
                    <span class="badge badge-amber">Suspendu</span>
                  }
                </td>
                <td class="px-4 py-3 text-right">
                  @if (user.id !== currentUserId()) {
                    <button
                      (click)="toggleActive(user)"
                      class="btn btn-secondary btn-sm"
                    >
                      {{ user.is_active ? 'Suspendre' : 'Réactiver' }}
                    </button>
                  }
                </td>
              </tr>
            } @empty {
              <tr>
                <td colspan="5" class="px-4 py-10 text-center text-sm text-slate-400">Aucun utilisateur.</td>
              </tr>
            }
          </tbody>
        </table>
      </div>

      <div class="text-xs text-slate-400 flex items-center justify-between">
        <span>{{ users().length }} utilisateur(s)</span>
        <button (click)="load()" class="btn btn-secondary btn-sm">Recharger</button>
      </div>
    </div>
  `
})
export class AdminUsersComponent implements OnInit {
    api = inject(ApiService);
    auth = inject(AuthService);

    users = signal<User[]>([]);
    showCreate = signal(false);
    creating = signal(false);
    newUser = { username: '', password: '', email: '', role: '' };
    errorMessage = signal('');
    successMessage = signal('');
    currentUserId = signal(0);

    ngOnInit() {
        this.currentUserId.set(this.auth.currentUser()?.id ?? 0);
        this.load();
    }

    load() {
        this.errorMessage.set('');
        this.api.getUsers().subscribe({
            next: (page) => this.users.set(page.data),
            error: () => this.errorMessage.set('Impossible de charger les utilisateurs.')
        });
    }

    createUser() {
        if (!this.newUser.username || !this.newUser.email || !this.newUser.password || !this.newUser.role) {
            this.errorMessage.set('Tous les champs sont obligatoires.');
            return;
        }
        this.errorMessage.set('');
        this.creating.set(true);
        this.api.createUser({ ...this.newUser }).subscribe({
            next: (res) => {
                this.creating.set(false);
                if (res.success) {
                    this.successMessage.set(res.message || 'Utilisateur créé.');
                    this.cancelCreate();
                    this.load();
                } else {
                    this.errorMessage.set(res.message || 'Échec de la création.');
                }
            },
            error: (err) => {
                this.creating.set(false);
                this.errorMessage.set(err?.error?.error || err?.error?.message || 'Erreur lors de la création.');
            }
        });
    }

    cancelCreate() {
        this.newUser = { username: '', password: '', email: '', role: '' };
        this.showCreate.set(false);
    }

    changeRole(user: User, role: string) {
        if (!role) return;
        this.successMessage.set('');
        this.api.updateUser(user.id!, { role, is_active: user.is_active }).subscribe({
            next: (res) => {
                if (res.success) {
                    this.successMessage.set(`Rôle de « ${user.username} » mis à jour.`);
                    this.load();
                } else {
                    this.errorMessage.set(res.message || 'Mise à jour impossible.');
                }
            },
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Erreur lors du changement de rôle.')
        });
    }

    toggleActive(user: User) {
        this.successMessage.set('');
        this.api.updateUser(user.id!, { role: user.role, is_active: !user.is_active }).subscribe({
            next: (res) => {
                if (res.success) {
                    this.successMessage.set(user.is_active ? `Compte « ${user.username} » suspendu.` : `Compte « ${user.username} » réactivé.`);
                    this.load();
                } else {
                    this.errorMessage.set(res.message || 'Mise à jour impossible.');
                }
            },
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Erreur lors de la mise à jour.')
        });
    }
}