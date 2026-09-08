import { Component, inject } from '@angular/core';
import { RouterLink, RouterOutlet, RouterLinkActive } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({

    selector: 'app-layout',
    standalone: true,
    imports: [RouterOutlet, RouterLink, RouterLinkActive],
    template: `
    <div class="min-h-screen flex bg-slate-100">
      <!-- Sidebar -->
      <aside class="w-64 bg-white border-r border-slate-200 flex flex-col justify-between">
        <div>
          <!-- Logo -->
          <div class="flex items-center gap-3 px-4 py-5">
            <div class="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center text-white font-extrabold text-lg shadow-sm">
              KP
            </div>
            <div>
              <h1 class="text-slate-900 font-bold text-base tracking-tight leading-tight">KPay</h1>
              <p class="text-xs text-slate-400">Système de paie</p>
            </div>
          </div>

          <!-- Navigation -->
          <nav class="px-3 space-y-0.5">
            <a routerLink="/dashboard" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 00-1-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 00-1 1m-6 0h6"/></svg>
              Tableau de bord
            </a>

            <a routerLink="/employees" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/></svg>
              Employés
            </a>

            <a routerLink="/payroll" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>
              Gestion de la Paie
            </a>

            <a routerLink="/leaves" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>
              Congés & Absences
            </a>

            <a routerLink="/my-payslips" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
              Mes bulletins
            </a>

            <a routerLink="/my-profile" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>
              Mon profil
            </a>

            <a routerLink="/profile-changes" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"/></svg>
              Validations profil
            </a>

            @if (isTaxRulesVisible()) {
              <a routerLink="/admin/tax-rules" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
                Règles sociales
              </a>
            }

            @if (canManageSettings()) {
              <a routerLink="/admin/settings" routerLinkActive="bg-blue-50 text-blue-700" class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-slate-100 transition-colors text-sm font-medium text-slate-600">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                Paramètres RH
              </a>
            }
          </nav>
        </div>

        <!-- Profil & Déconnexion -->
        <div class="border-t border-slate-200 p-3">
          <div class="flex items-center justify-between rounded-lg px-3 py-2">
            <div class="min-w-0">
              <p class="text-sm font-semibold text-slate-800 truncate">{{ authService.currentUser()?.username || 'Utilisateur' }}</p>
              <p class="text-xs text-slate-400 capitalize">{{ authService.currentUser()?.role || 'Admin' }}</p>
            </div>
            <button (click)="authService.logout()" class="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-lg transition-colors" title="Déconnexion">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/></svg>
            </button>
          </div>
        </div>
      </aside>

      <!-- Zone Principale -->
      <div class="flex-1 flex flex-col overflow-hidden">
        <!-- Header -->
        <header class="bg-white border-b border-slate-200 h-16 flex items-center justify-between px-8">
          <h2 class="text-base font-semibold text-slate-900 tracking-tight">Système de paie KPay</h2>
          <div class="flex items-center gap-4 text-sm">
            <span class="inline-flex items-center gap-1.5 text-slate-500 tabular-nums">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 inline-block"></span>
              {{ todayLabel }}
            </span>
          </div>
        </header>

        <!-- Contenu des pages -->
        <main class="flex-1 overflow-y-auto p-8">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
  `
})
export class LayoutComponent {
    authService = inject(AuthService);

    todayLabel = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date());

    isTaxRulesVisible(): boolean {
        const role = this.authService.currentUser()?.role || '';
        return role === 'admin' || role === 'accountant';
    }

    canManageSettings(): boolean {
        const role = this.authService.currentUser()?.role || '';
        return role === 'admin' || role === 'payroll_officer';
    }
}
