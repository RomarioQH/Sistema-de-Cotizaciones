import { inject, Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, catchError, map, Observable, of, tap, throwError } from 'rxjs';
import { API_BASE_URL } from './api-url.token';

export type UserRole = 'admin' | 'vendedor' | 'cliente';
export interface AuthUser {
  id: string;
  name: string;
  email: string;
  phone?: string;
  company?: string;
  role: UserRole;
  status: string;
}
interface Envelope<T> { isSuccess: boolean; data?: T; errorMessage?: string; }
export interface LoginResult {
  accessToken?: string;
  idToken?: string;
  refreshToken?: string;
  expiresIn?: number;
  user?: AuthUser;
  challengeName?: string;
  session?: string;
  username?: string;
}

const KEYS = {
  idToken: 'cotizaciones.idToken',
  accessToken: 'cotizaciones.accessToken',
  refreshToken: 'cotizaciones.refreshToken',
  user: 'cotizaciones.user',
} as const;

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL);
  private readonly userSubject = new BehaviorSubject<AuthUser | null>(this.readUser());
  readonly user$ = this.userSubject.asObservable();

  get currentUser(): AuthUser | null { return this.userSubject.value; }
  get idToken(): string | null { return sessionStorage.getItem(KEYS.idToken); }
  get accessToken(): string | null { return sessionStorage.getItem(KEYS.accessToken); }
  get refreshToken(): string | null { return sessionStorage.getItem(KEYS.refreshToken); }
  isAuthenticated(): boolean { return !!this.idToken && !!this.currentUser; }

  /** Revalidate the stored identity and the active SQL profile after refreshing the browser. */
  loadProfile(): Observable<AuthUser> {
    return this.http.get<Envelope<AuthUser>>(`${this.base}/auth/me`).pipe(
      map((r) => this.unwrap(r)),
      tap((user) => { sessionStorage.setItem(KEYS.user, JSON.stringify(user)); this.userSubject.next(user); }),
    );
  }

  login(email: string, password: string): Observable<LoginResult> {
    return this.http.post<Envelope<LoginResult>>(`${this.base}/auth/login`, { email, password }).pipe(
      map((r) => this.unwrap(r)),
      tap((r) => { if (r.idToken && r.accessToken && r.user) this.saveSession(r); }),
    );
  }

  register(payload: { name: string; email: string; password: string; phone?: string; company?: string }) {
    return this.request<{ email: string; confirmationRequired: boolean; message: string }>('/auth/register', payload);
  }
  confirmRegistration(email: string, code: string) {
    return this.request<{ message: string }>('/auth/confirm-registration', { email, code });
  }
  forgotPassword(email: string) {
    return this.request<{ message: string }>('/auth/forgot-password', { email });
  }
  confirmPassword(email: string, code: string, newPassword: string) {
    return this.request<{ message: string }>('/auth/confirm-password', { email, code, newPassword });
  }
  completeNewPassword(username: string, session: string, newPassword: string) {
    return this.http.post<Envelope<LoginResult>>(`${this.base}/auth/complete-new-password`, { username, session, newPassword }).pipe(
      map((r) => this.unwrap(r)),
      tap((r) => { if (r.idToken && r.accessToken && r.user) this.saveSession(r); }),
    );
  }
  refreshSession(): Observable<LoginResult> {
    const refreshToken = this.refreshToken;
    if (!refreshToken) return throwError(() => new Error('La sesión expiró. Inicia sesión nuevamente.'));
    return this.http.post<Envelope<LoginResult>>(`${this.base}/auth/refresh`, { refreshToken }).pipe(
      map((r) => this.unwrap(r)),
      tap((r) => {
        if (r.idToken) sessionStorage.setItem(KEYS.idToken, r.idToken);
        if (r.accessToken) sessionStorage.setItem(KEYS.accessToken, r.accessToken);
      }),
      catchError((error) => { this.clearSession(); return throwError(() => error); }),
    );
  }
  logout(): Observable<unknown> {
    const accessToken = this.accessToken;
    const call$ = accessToken
      ? this.http.post<Envelope<unknown>>(`${this.base}/auth/logout`, { accessToken })
      : of({ isSuccess: true, data: { message: 'Sesión cerrada en este dispositivo.' } });
    return call$.pipe(
      catchError(() => of({ isSuccess: true, data: { message: 'Sesión cerrada localmente.' } })),
      tap(() => this.clearSession()),
    );
  }

  private request<T>(path: string, payload: unknown): Observable<T> {
    return this.http.post<Envelope<T>>(`${this.base}${path}`, payload).pipe(map((r) => this.unwrap(r)));
  }
  private unwrap<T>(r: Envelope<T>): T {
    if (!r?.isSuccess) throw new Error(r?.errorMessage || 'La solicitud no pudo completarse.');
    return r.data as T;
  }
  private saveSession(r: LoginResult): void {
    if (r.idToken) sessionStorage.setItem(KEYS.idToken, r.idToken);
    if (r.accessToken) sessionStorage.setItem(KEYS.accessToken, r.accessToken);
    if (r.refreshToken) sessionStorage.setItem(KEYS.refreshToken, r.refreshToken);
    if (r.user) { sessionStorage.setItem(KEYS.user, JSON.stringify(r.user)); this.userSubject.next(r.user); }
  }
  private readUser(): AuthUser | null {
    try { const raw = sessionStorage.getItem(KEYS.user); return raw ? JSON.parse(raw) as AuthUser : null; }
    catch { return null; }
  }
  private clearSession(): void {
    Object.values(KEYS).forEach((key) => sessionStorage.removeItem(key));
    this.userSubject.next(null);
  }
}
