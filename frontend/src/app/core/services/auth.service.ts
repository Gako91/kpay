import { Injectable, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, tap } from 'rxjs';
import { AuthResponse, LoginRequest, MfaLoginRequest, User } from '../models/kpay.models';

@Injectable({
    providedIn: 'root'
})
export class AuthService {
    private readonly TOKEN_KEY = 'kpay_jwt_token';
    private readonly USER_KEY = 'kpay_user';

    // Signaux Angular pour la gestion réactive de l'état d'authentification
    currentUser = signal<User | null>(this.getStoredUser());
    isAuthenticated = signal<boolean>(!!this.getToken());

    constructor(private http: HttpClient, private router: Router) { }

    login(credentials: LoginRequest): Observable<AuthResponse> {
        return this.http.post<AuthResponse>('/api/v1/auth/login', credentials).pipe(
            tap((response) => {
                // Si un challenge MFA est demandé, on ne stocke pas encore la session.
                if (response.challenge === 'totp') {
                    return;
                }
                this.saveSession(response);
            })
        );
    }

    loginMfa(request: MfaLoginRequest): Observable<AuthResponse> {
        return this.http.post<AuthResponse>('/api/v1/auth/login/mfa', request).pipe(
            tap((response) => this.saveSession(response))
        );
    }

    saveSsoSession(token: string, sub: string, role: string, org: number): void {
        const response: AuthResponse = { success: true, token, sub, role, org: Number(org), expires: '' };
        this.saveSession(response);
    }

    logout(): void {
        localStorage.removeItem(this.TOKEN_KEY);
        localStorage.removeItem(this.USER_KEY);
        this.currentUser.set(null);
        this.isAuthenticated.set(false);
        this.router.navigate(['/login']);
    }

    getToken(): string | null {
        return localStorage.getItem(this.TOKEN_KEY);
    }

    private saveSession(response: AuthResponse): void {
        if (!response.token) {
            return;
        }
        const user: User = {
            id: 0,
            organization_id: response.org,
            username: response.sub,
            role: (response.role as User['role']) || 'employee',
            email: '',
            is_active: true
        };
        localStorage.setItem(this.TOKEN_KEY, response.token);
        localStorage.setItem(this.USER_KEY, JSON.stringify(user));
        this.currentUser.set(user);
        this.isAuthenticated.set(true);
    }

    private getStoredUser(): User | null {
        const userStr = localStorage.getItem(this.USER_KEY);
        return userStr ? JSON.parse(userStr) : null;
    }
}