import { InjectionToken } from '@angular/core';

/** Provide the API Gateway stage URL, without a trailing slash. */
export const API_BASE_URL = new InjectionToken<string>('API_BASE_URL');
