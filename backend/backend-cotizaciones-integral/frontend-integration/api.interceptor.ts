import { HttpInterceptorFn } from '@angular/common/http';

/** For a REST API Cognito User Pool authorizer configured without OAuth scopes, send the ID token. */
export const apiAuthInterceptor: HttpInterceptorFn = (req, next) => {
  const idToken = sessionStorage.getItem('cotizaciones.idToken');
  if (!idToken || req.url.includes('/auth/login') || req.url.includes('/auth/register') ||
      req.url.includes('/auth/confirm-registration') || req.url.includes('/auth/forgot-password') ||
      req.url.includes('/auth/confirm-password') || req.url.includes('/auth/complete-new-password') ||
      req.url.includes('/auth/refresh')) {
    return next(req);
  }
  return next(req.clone({ setHeaders: { Authorization: `Bearer ${idToken}` } }));
};
