/* Merge these providers into the existing Angular appConfig.ts; do not replace other providers. */
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { API_BASE_URL } from './frontend-integration/api-url.token';
import { apiAuthInterceptor } from './frontend-integration/api.interceptor';

// Example inside the existing providers array:
// provideHttpClient(withInterceptors([apiAuthInterceptor])),
// { provide: API_BASE_URL, useValue: environment.apiUrl },
