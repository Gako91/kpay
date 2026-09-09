import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { ApiService } from '../../core/services/api.service';

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
          <h1 class="text-xl font-semibold tracking-tight text-slate-900">
            @if (mfaStep()) { Vérification en deux étapes } @else { Connexion à KPay }
          </h1>
          <p class="text-sm text-slate-500 mt-1">
            @if (mfaStep()) { Saisissez le code de votre application d'authentification } @else { Accédez à votre espace de paie }
          </p>
        </div>

        <div class="bg-white rounded-2xl border border-slate-200 shadow-sm p-6">
          @if (errorMessage()) {
            <div class="alert alert-error mb-5">
              {{ errorMessage() }}
            </div>
          }

          @if (!mfaStep()) {
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

              @if (ssoEnabled()) {
                <div class="flex items-center gap-3 my-1">
                  <div class="h-px bg-slate-200 flex-1"></div>
                  <span class="text-xs text-slate-400">ou</span>
                  <div class="h-px bg-slate-200 flex-1"></div>
                </div>
                <a href="/api/v1/auth/sso/authorize" class="btn btn-secondary w-full justify-center">
                  <svg class="w-4 h-4 mr-1.5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 2a10 10 0 100 20 10 10 0 000-20zm1 17.9v-1.4a1.5 1.5 0 00-3 0v1.4a8 8 0 01-5-6.9h1.4a1.5 1.5 0 000-3H5a8 8 0 017-5v1.4a1.5 1.5 0 003 0V2.1a8 8 0 015 6.9h-1.4a1.5 1.5 0 000 3h1.4a8 8 0 01-5 6.9z"/></svg>
                  Connexion SSO
                </a>
              }
            </form>
          } @else {
            <form (ngSubmit)="onMfa()" class="space-y-5">
              <div>
                <label class="label text-slate-700">Code MFA</label>
                <input
                  type="text"
                  [(ngModel)]="mfaCode"
                  name="mfaCode"
                  required
                  class="input text-center tracking-[0.35em] text-lg"
                  placeholder="______"
                  maxlength="6"
                  inputmode="numeric"
                  autocomplete="one-time-code"
                />
                <p class="text-xs text-slate-400 mt-2">Code à 6 chiffres ou code de secours.</p>
              </div>

              <button
                type="submit"
                [disabled]="isLoading()"
                class="btn btn-primary w-full"
              >
                @if (isLoading()) {
                  <span class="inline-block animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full"></span>
                  Vérification...
                } @else {
                  Valider
                }
              </button>

              <button type="button" (click)="backToLogin()" class="w-full text-center text-sm text-slate-500 hover:text-slate-700">
                Retour à la connexion
              </button>
            </form>
          }
        </div>
      </div>
    </div>
  `
})
export class LoginComponent implements OnInit {
    username = '';
    password = '';
    mfaCode = '';
    mfaToken = '';
    mfaStep = signal(false);
    isLoading = signal(false);
    errorMessage = signal('');
    ssoEnabled = signal(false);

    private authService = inject(AuthService);
    private apiService = inject(ApiService);
    private router = inject(Router);
    private route = inject(ActivatedRoute);

    ngOnInit(): void {
        // Retour SSO : le JWT arrive dans le fragment (#sso=...&sub=...&role=...&org=...)
        this.route.fragment.subscribe((frag) => {
            if (frag && frag.includes('sso=')) {
                const params = new URLSearchParams(frag);
                const token = params.get('sso') || '';
                const sub = params.get('sub') || '';
                const role = params.get('role') || 'employee';
                const org = Number(params.get('org') || '1');
                if (token) {
                    this.authService.saveSsoSession(token, sub, role, org);
                    this.router.navigate(['/dashboard']);
                }
            }
        });
        const ssoErr = this.route.snapshot.queryParamMap.get('sso_error');
        if (ssoErr) {
            this.errorMessage.set(ssoErr);
        }
        this.apiService.getSsoConfig().subscribe({
            next: (cfg) => this.ssoEnabled.set(cfg.enabled),
            error: () => this.ssoEnabled.set(false)
        });
    }

    onLogin(): void {
        if (!this.username || !this.password) {
            this.errorMessage.set('Veuillez remplir tous les champs.');
            return;
        }

        this.isLoading.set(true);
        this.errorMessage.set('');

        this.authService.login({ username: this.username, password: this.password }).subscribe({
            next: (res) => {
                this.isLoading.set(false);
                if (res.challenge === 'totp' && res.mfa_token) {
                    this.mfaToken = res.mfa_token;
                    this.mfaStep.set(true);
                    return;
                }
                this.router.navigate(['/dashboard']);
            },
            error: (err) => {
                this.isLoading.set(false);
                const apiMsg = err?.error?.error || err?.error?.message || 'Identifiants invalides.';
                this.errorMessage.set(apiMsg);
            }
        });
    }

    onMfa(): void {
        if (!this.mfaCode) {
            this.errorMessage.set('Veuillez saisir votre code.');
            return;
        }
        this.isLoading.set(true);
        this.errorMessage.set('');
        this.authService.loginMfa({ mfa_token: this.mfaToken, code: this.mfaCode.trim() }).subscribe({
            next: () => {
                this.isLoading.set(false);
                this.router.navigate(['/dashboard']);
            },
            error: (err) => {
                this.isLoading.set(false);
                this.errorMessage.set(err?.error?.error || err?.error?.message || 'Code MFA invalide.');
            }
        });
    }

    backToLogin(): void {
        this.mfaStep.set(false);
        this.mfaCode = '';
        this.mfaToken = '';
        this.errorMessage.set('');
    }
}