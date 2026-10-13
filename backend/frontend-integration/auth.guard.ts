import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService, UserRole } from './auth.service';

/** UX guard only. Lambda/API Gateway remains the authorization boundary. */
export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.isAuthenticated() ? true : router.createUrlTree(['/']);
};

export const roleGuard = (allowed: UserRole[]): CanActivateFn => () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (!auth.isAuthenticated()) return router.createUrlTree(['/']);
  return auth.currentUser && allowed.includes(auth.currentUser.role)
    ? true
    : router.createUrlTree([`/${auth.currentUser?.role ?? 'cliente'}/dashboard`]);
};
