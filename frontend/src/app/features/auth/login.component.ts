import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({
    selector: 'app-login',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="min-h-screen bg-slate-900 flex items-center justify-center p-4">
      <div class="bg-white rounded-2xl shadow-2xl p-8 w-full max-w-md border border-slate-800">
        <div class="text-center mb-8">
          <div class="w-16 h-16 bg-blue-600 rounded-2xl flex items-center justify-center text-white text-3xl font-extrabold mx-auto mb-4 shadow-lg shadow-blue-500/30">
            KP
          </div>
          <h1 class="text-2xl font-bold text-slate-800">Connexion à KPay</h1>
          <p class="text-slate-500 text-sm mt-1">Saisissez vos identifiants pour accéder à la plateforme</p>
        </div>

        @if (errorMessage()) {
          <div class="bg-rose-50 border border-rose-200 text-rose-700 px-4 py-3 rounded-lg text-sm mb-6">
            {{ errorMessage() }}
          </div>
        }

        <form (ngSubmit)="onLogin()" class="space-y-5">
          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1">Nom d'utilisateur</label>
            <input
              type="text"
              [(ngModel)]="username"
              name="username"
              required
              class="w-full px-4 py-2.5 rounded-lg border border-slate-300 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition text-sm"
              placeholder="ex: admin"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1">Mot de passe</label>
            <input
              type="password"
              [(ngModel)]="password"
              name="password"
              required
              class="w-full px-4 py-2.5 rounded-lg border border-slate-300 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition text-sm"
              placeholder="••••••••"
            />
          </div>

          <button
            type="submit"
            [disabled]="isLoading()"
            class="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2.5 rounded-lg shadow-lg shadow-blue-500/30 transition duration-200 flex items-center justify-center gap-2"
          >
            @if (isLoading()) {
              <span class="inline-block animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
              Connexion...
            } @else {
              Se connecter
            }
          </button>
        </form>
      </div>
    </div>
  `
})
export class LoginComponent {
    username = '';
    password = '';
    isLoading = signal(false);
    errorMessage = signal('');

    private authService = inject(AuthService);
    private router = inject(Router);

    onLogin(): void {
        if (!this.username || !this.password) {
            this.errorMessage.set('Veuillez remplir tous les champs.');
            return;
        }

        this.isLoading.set(true);
        this.errorMessage.set('');

        this.authService.login({ username: this.username, password: this.password }).subscribe({
            next: () => {
                this.isLoading.set(false);
                this.router.navigate(['/dashboard']);
            },
            error: (err) => {
                this.isLoading.set(false);
                const apiMsg = err?.error?.error || err?.error?.message || 'Identifiants invalides.';
                this.errorMessage.set(apiMsg);
            }
        });
    }
}
