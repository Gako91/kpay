import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';

export const apiInterceptor: HttpInterceptorFn = (req, next) => {
    const authService = inject(AuthService);
    const token = authService.getToken();

    // En-tête à ajouter par défaut (Token JWT si présent)
    let headers = req.headers;

    if (token) {
        headers = headers.set('Authorization', `Bearer ${token}`);
    }

    const authReq = req.clone({ headers });
    return next(authReq);
};