import { Component, inject, OnInit, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { Employee, Payslip } from '../../core/models/kpay.models';

@Component({
    selector: 'app-dashboard',
    standalone: true,
    imports: [DecimalPipe],
    template: `

    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-slate-800">Tableau de Bord</h1>
        <p class="text-slate-500 text-sm">Aperçu général de la gestion de la paie et des effectifs.</p>
      </div>

      <!-- Métriques KPIs -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div class="bg-white p-6 rounded-xl border border-slate-200 shadow-sm">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-slate-500">Employés Actifs</span>
            <div class="p-2 bg-blue-50 text-blue-600 rounded-lg">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/></svg>
            </div>
          </div>
          <p class="text-3xl font-bold text-slate-800 mt-4">{{ employees().length }}</p>
        </div>

        <div class="bg-white p-6 rounded-xl border border-slate-200 shadow-sm">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-slate-500">Bulletins ce Mois</span>
            <div class="p-2 bg-emerald-50 text-emerald-600 rounded-lg">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
            </div>
          </div>
          <p class="text-3xl font-bold text-slate-800 mt-4">{{ payslips().length }}</p>
        </div>

        <div class="bg-white p-6 rounded-xl border border-slate-200 shadow-sm">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-slate-500">Masse Salariale Brute</span>
            <div class="p-2 bg-purple-50 text-purple-600 rounded-lg">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
            </div>
          </div>
          <p class="text-3xl font-bold text-slate-800 mt-4">{{ totalGrossPay() | number }} FCFA</p>
        </div>

        <div class="bg-white p-6 rounded-xl border border-slate-200 shadow-sm">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-slate-500">Aujourd'hui</span>
            <div class="p-2 bg-amber-50 text-amber-600 rounded-lg">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>
            </div>
          </div>
          <p class="text-lg font-bold text-slate-800 mt-5">05 Septembre 2026</p>
        </div>
      </div>

      <!-- Action donnees indisponibles -->
      @if (errorMessage()) {
        <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm">{{ errorMessage() }}</div>
      }

      <!-- Actions Rapides -->
      <div class="bg-white p-6 rounded-xl border border-slate-200 shadow-sm">
        <h2 class="text-lg font-bold text-slate-800 mb-4">Actions Rapides</h2>
        <div class="flex flex-wrap gap-4">
          <button class="bg-blue-600 hover:bg-blue-700 text-white font-medium px-4 py-2.5 rounded-lg text-sm transition shadow">
            + Ajouter un Employé
          </button>
          <button class="bg-emerald-600 hover:bg-emerald-700 text-white font-medium px-4 py-2.5 rounded-lg text-sm transition shadow">
            ⚡ Lancer le Calcul de Paie
          </button>
        </div>
      </div>
    </div>
  `
})
export class DashboardComponent implements OnInit {
    private apiService = inject(ApiService);

    employees = signal<Employee[]>([]);
    payslips = signal<Payslip[]>([]);
    errorMessage = signal('');

    ngOnInit(): void {
        this.loadData();
    }

    loadData(): void {
        this.apiService.getEmployees().subscribe({
            next: (data) => this.employees.set(data),
            error: (err) => {
                this.employees.set([]);
                this.errorMessage.set('Impossible de charger les employés.');
            }
        });

        this.apiService.getPayslips().subscribe({
            next: (data) => this.payslips.set(data),
            error: () => {
                this.payslips.set([]);
                this.errorMessage.set('Impossible de charger les bulletins.');
            }
        });
    }

    totalGrossPay(): number {
        return this.payslips().reduce((acc, p) => acc + p.gross_amount, 0);
    }
}
