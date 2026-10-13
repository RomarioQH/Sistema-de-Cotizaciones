import { inject, Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { map, Observable } from 'rxjs';
import { API_BASE_URL } from './api-url.token';

interface Envelope<T> { isSuccess: boolean; data?: T; errorMessage?: string; }
export interface Product { id: string; sku: string; title: string; category: string; description: string; price: number; currency: string; }
export interface QuoteListItem {
  id: string; clientId: string; clientName: string; clientEmail?: string; clientCompany?: string;
  sellerId?: string; sellerName?: string; status: string; date: string; itemCount: number;
  subtotal: number; discountAmount: number; taxAmount: number; total: number; currency: string;
  items: unknown[];
}

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL);

  products(search = '', category = ''): Observable<Product[]> {
    let params = new HttpParams();
    if (search) params = params.set('search', search);
    if (category) params = params.set('category', category);
    return this.get<Product[]>('/productos', params);
  }
  quotes(search = '', status = ''): Observable<QuoteListItem[]> {
    let params = new HttpParams();
    if (search) params = params.set('search', search);
    if (status) params = params.set('status', status);
    return this.get<QuoteListItem[]>('/cotizaciones', params);
  }
  quote(quoteCode: string): Observable<QuoteListItem & { items: unknown[]; history: unknown[] }> {
    return this.get(`/cotizaciones/${encodeURIComponent(quoteCode)}`);
  }
  createQuote(payload: { items: { productId: string; quantity: number }[]; discountPercent?: number; taxPercent?: number; customerMessage?: string; customerId?: string; sellerId?: string }) {
    return this.post<{ quoteId: number; quoteCode: string; subtotal: number; discountAmount: number; taxAmount: number; total: number }>('/cotizaciones', payload);
  }
  changeQuoteStatus(quoteCode: string, status: 'Enviada' | 'Aceptada' | 'Rechazada', comment = '') {
    return this.patch(`/cotizaciones/${encodeURIComponent(quoteCode)}/estado`, { status, comment });
  }
  sendQuote(quoteCode: string) {
    return this.post(`/cotizaciones/${encodeURIComponent(quoteCode)}/enviar`, {});
  }
  users(search = ''): Observable<unknown[]> {
    let params = new HttpParams(); if (search) params = params.set('search', search);
    return this.get('/usuarios', params);
  }
  createUser(payload: { name: string; email: string; role: 'vendedor' | 'cliente'; phone?: string; company?: string }) {
    return this.post('/usuarios', payload);
  }
  updateUser(userId: string, payload: Record<string, unknown>) {
    return this.patch(`/usuarios/${encodeURIComponent(userId)}`, payload);
  }
  dashboard(role: 'admin' | 'vendedor' | 'cliente') { return this.get(`/dashboard/${role}`); }
  reports() { return this.get('/reportes'); }

  private get<T>(path: string, params = new HttpParams()): Observable<T> {
    return this.http.get<Envelope<T>>(`${this.base}${path}`, { params }).pipe(map((r) => this.unwrap(r)));
  }
  private post<T = unknown>(path: string, body: unknown): Observable<T> {
    return this.http.post<Envelope<T>>(`${this.base}${path}`, body).pipe(map((r) => this.unwrap(r)));
  }
  private patch<T = unknown>(path: string, body: unknown): Observable<T> {
    return this.http.patch<Envelope<T>>(`${this.base}${path}`, body).pipe(map((r) => this.unwrap(r)));
  }
  private unwrap<T>(r: Envelope<T>): T {
    if (!r?.isSuccess) throw new Error(r?.errorMessage || 'La solicitud no pudo completarse.');
    return r.data as T;
  }
}
