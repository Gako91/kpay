import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({
    selector: 'app-login',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="min-h-screen bg-slate-100 flex items-center justify-center p-4">
      <div class="w-full max-w-sm">
        <div class="mb-8 text-center">
          <div class="w-12 h-12 bg-blue-600 rounded-xl flex items-center justify-center text-white text-xl font-extrabold mx-auto mb-4 shadow-sm">
            KP
          </div>
          <h1 class="text-xl font-semibold tracking-tight text-slate-900">Connexion à KPay</h1>
          <p class="text-sm text-slate-500 mt-1">Accédez à votre espace de paie</p>
        </div>

        <div class="bg-white rounded-2xl border border-slate-200 shadow-sm p-6">
          @if (errorMessage()) {
            <div class="alert alert-error mb-5">
              {{ errorMessage() }}
            </div>
          }

          <form (ngSubmit)="onLogin()" class="space-y-5">
            <div>
              <label class="label text-slate-700">Nom d'utilisateur</label>
              <input
                type="text"
                [(ngModel)]="username"
                name="username"
                required
                class="input"
                placeholder="ex: admin"
              />
            </div>

            <div>
              <label class="label text-slate-700">Mot de passe</label>
              <input
                type="password"
                [(ngModel)]="password"
                name="password"
                required
                class="input"
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              [disabled]="isLoading()"
              class="btn btn-primary w-full"
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
