import { Injectable, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, tap } from 'rxjs';
import { AuthResponse, LoginRequest, User } from '../models/kpay.models';

@Injectable({
    providedIn: 'root'
})
export class AuthService {
    private readonly TOKEN_KEY = 'kpay_jwt_token';
    private readonly USER_KEY = 'kpay_user';

    // Signals Angular pour la gestion réactive de l'état d'authentification
    currentUser = signal<User | null>(this.getStoredUser());
    isAuthenticated = signal<boolean>(!!this.getToken());

    constructor(private http: HttpClient, private router: Router) { }

    login(credentials: LoginRequest): Observable<AuthResponse> {
        return this.http.post<AuthResponse>('/api/v1/auth/login', credentials).pipe(
            tap((response) => {
                // Le backend renvoie { token, sub, role, expires } et non un objet user complet
                const user: User = {
                    id: 0,
                    organization_id: 1,
                    username: response.sub,
                    role: (response.role as User['role']) || 'employee',
                    email: '',
                    is_active: true
                };
                this.saveSession(response.token, user);
            })
        );
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

    private saveSession(token: string, user: User): void {
        localStorage.setItem(this.TOKEN_KEY, token);
        localStorage.setItem(this.USER_KEY, JSON.stringify(user));
        this.currentUser.set(user);
        this.isAuthenticated.set(true);
    }

    private getStoredUser(): User | null {
        const userStr = localStorage.getItem(this.USER_KEY);
        return userStr ? JSON.parse(userStr) : null;
    }
}