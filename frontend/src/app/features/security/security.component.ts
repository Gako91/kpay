import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { UserSsoLink } from '../../core/models/kpay.models';

@Component({
    selector: 'app-security',
    standalone: true,
    imports: [FormsModule],
    template: `
    <div class="space-y-6 max-w-2xl">
      <div class="page-head">
        <div>
          <h1 class="page-title">Sécurité</h1>
          <p class="page-subtitle">Authentification à deux facteurs (TOTP) et connexion SSO de votre compte.</p>
        </div>
      </div>

      @if (errorMessage()) {
        <div class="alert alert-error">{{ errorMessage() }}</div>
      }
      @if (successMessage()) {
        <div class="alert alert-success">{{ successMessage() }}</div>
      }

      <!-- ============ MFA TOTP ============ -->
      <div class="card p-6 space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="font-semibold text-slate-800">Authentification à deux facteurs</h2>
            <p class="text-sm text-slate-500 mt-1">
              @if (mfaEnabled()) {
                Le MFA est <span class="badge badge-emerald">activé</span> — {{ backupCount() }} code(s) de secours restant(s).
              } @else {
                Le MFA protège votre compte avec un code à 6 chiffres généré par une application (Google Authenticator, FreeOTP…).
              }
            </p>
          </div>
          @if (mfaEnabled()) {
            <button (click)="startDisable()" class="btn btn-danger">Désactiver</button>
          }
        </div>

        @if (!mfaEnabled() && enrollment()) {
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-5 space-y-4">
            <div class="grid md:grid-cols-2 gap-5">
              <div>
                <label class="label">Secret</label>
                <input class="input font-mono" [value]="enrollment()!.secret" readonly onclick="this.select()" />
                <p class="text-xs text-slate-400 mt-1.5">Renseignez ce secret dans votre application d'authentification.</p>
              </div>
              <div class="flex flex-col items-center justify-center">
                <img class="rounded-lg border border-slate-200 w-36 h-36" [src]="qrUrl()" alt="QR code MFA" />
                <p class="text-xs text-slate-400 mt-2">Scannez avec votre application</p>
              </div>
            </div>

            <div>
              <label class="label">Codes de secours (à conserver précieusement)</label>
              <div class="grid grid-cols-2 gap-2">
                @for (code of enrollment()!.backup_codes; track code) {
                  <div class="font-mono text-sm bg-white border border-slate-200 rounded-lg px-3 py-1.5 text-center text-slate-700">{{ code }}</div>
                }
              </div>
            </div>

            <div class="pt-2 border-t border-slate-200">
              <label class="label">Valider le premier code pour activer le MFA</label>
              <div class="flex gap-3">
                <input type="text" maxlength="6" [(ngModel)]="verifyCode" name="verifyCode" class="input w-40 text-center tracking-[0.3em]" placeholder="______" />
                <button (click)="verify()" class="btn btn-primary" [disabled]="verifyCode.length < 6">Activer le MFA</button>
                <button (click)="enrollment.set(null)" class="btn btn-secondary">Annuler</button>
              </div>
            </div>
          </div>
        }

        @if (!mfaEnabled() && !enrollment()) {
          <button (click)="startEnroll()" class="btn btn-primary">Activer le MFA TOTP</button>
        }

        @if (mfaEnabled() && disabling()) {
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-5">
            <label class="label">Mot de passe pour confirmer la désactivation</label>
            <div class="flex gap-3">
              <input type="password" [(ngModel)]="disablePassword" name="disablePassword" class="input" placeholder="••••••••" />
              <button (click)="disable()" class="btn btn-primary" [disabled]="!disablePassword">Confirmer</button>
              <button (click)="disabling.set(false)" class="btn btn-secondary">Annuler</button>
            </div>
          </div>
        }
      </div>

      <!-- ============ SSO OIDC ============ -->
      <div class="card p-6 space-y-4">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="font-semibold text-slate-800">Connexion SSO (OIDC)</h2>
            <p class="text-sm text-slate-500 mt-1">
              @if (ssoConfig()?.enabled) {
                Connectez votre compte à {{ ssoConfig()!.issuer }} pour vous connecter en un clic (email strict).
              } @else {
                Le SSO n'est pas configuré sur ce serveur. Contactez l'administrateur.
              }
            </p>
          </div>
        </div>

        @if (ssoLinks().length > 0) {
          <div class="data-table">
            <table class="w-full text-sm">
              <thead>
                <tr>
                  <th>Fournisseur</th>
                  <th>Email lié</th>
                  <th class="w-24"></th>
                </tr>
              </thead>
              <tbody>
                @for (link of ssoLinks(); track link.id) {
                  <tr>
                    <td class="capitalize font-medium text-slate-700">{{ link.provider }}</td>
                    <td class="text-slate-500">{{ link.email }}</td>
                    <td class="text-right">
                      <button (click)="unlink(link)" class="btn btn-danger btn-sm">Détacher</button>
                    </td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        } @else if (ssoConfig()?.enabled) {
          <p class="text-sm text-slate-500">Aucun fournisseur connecté.</p>
        }

        @if (ssoConfig()?.enabled && !ssoLinked()) {
          <div>
            <a href="/api/v1/auth/sso/authorize" class="btn btn-secondary">
              Connecter votre fournisseur SSO
            </a>
          </div>
        }
      </div>
    </div>
  `
})
export class SecurityComponent implements OnInit {
    api = inject(ApiService);

    mfaEnabled = signal(false);
    backupCount = signal(0);
    enrollment = signal<{ secret: string; otpauth_uri: string; backup_codes: string[] } | null>(null);
    verifyCode = '';
    disablePassword = '';
    disabling = signal(false);
    ssoConfig = signal<{ enabled: boolean; issuer: string } | null>(null);
    ssoLinks = signal<UserSsoLink[]>([]);
    errorMessage = signal('');
    successMessage = signal('');

    ngOnInit() {
        this.load();
    }

    load() {
        this.errorMessage.set('');
        this.api.getMfaStatus().subscribe({
            next: (s) => {
                this.mfaEnabled.set(s.enabled);
                this.backupCount.set(s.backup_codes_count);
            },
            error: () => this.mfaEnabled.set(false)
        });
        this.api.getSsoConfig().subscribe({
            next: (c) => this.ssoConfig.set(c),
            error: () => this.ssoConfig.set(null)
        });
        this.api.getMySsoLinks().subscribe({
            next: (links) => this.ssoLinks.set(links),
            error: () => this.ssoLinks.set([])
        });
    }

    ssoLinked(): boolean {
        return this.ssoLinks().length > 0;
    }

    qrUrl(): string {
        const uri = this.enrollment()?.otpauth_uri ?? '';
        return `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(uri)}`;
    }

    startEnroll() {
        this.errorMessage.set('');
        this.api.enrollMfa().subscribe({
            next: (res) => this.enrollment.set(res),
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Impossible de démarrer l\'enrôlement MFA.')
        });
    }

    verify() {
        if (this.verifyCode.length < 6) {
            this.errorMessage.set('Saisissez le code à 6 chiffres.');
            return;
        }
        this.errorMessage.set('');
        this.api.verifyMfa(this.verifyCode.trim()).subscribe({
            next: (res) => {
                if (res.success) {
                    this.enrollment.set(null);
                    this.mfaEnabled.set(true);
                    this.successMessage.set('MFA activé avec succès.');
                } else {
                    this.errorMessage.set(res.message || 'Code invalide.');
                }
            },
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Code invalide.')
        });
    }

    startDisable() {
        this.disabling.set(true);
        this.errorMessage.set('');
    }

    disable() {
        if (!this.disablePassword) {
            this.errorMessage.set('Mot de passe requis.');
            return;
        }
        this.errorMessage.set('');
        this.api.disableMfa(this.disablePassword).subscribe({
            next: (res) => {
                if (res.success) {
                    this.mfaEnabled.set(false);
                    this.backupCount.set(0);
                    this.disabling.set(false);
                    this.disablePassword = '';
                    this.successMessage.set('MFA désactivé.');
                } else {
                    this.errorMessage.set(res.message || 'Désactivation impossible.');
                }
            },
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Mot de passe incorrect.')
        });
    }

    unlink(link: UserSsoLink) {
        this.api.deleteMySsoLink(link.id).subscribe({
            next: () => {
                this.ssoLinks.set(this.ssoLinks().filter(l => l.id !== link.id));
                this.successMessage.set('Lien SSO détaché.');
            },
            error: (err) => this.errorMessage.set(err?.error?.error || err?.error?.message || 'Échec du détachement.')
        });
    }
}