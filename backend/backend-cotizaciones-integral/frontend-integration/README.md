# Integración con la web Angular existente

La auditoría del repo público encontró que el componente de login usa `DemoDataService.authenticate`, que el registro navega al dashboard sin crear cuenta, la recuperación muestra un mensaje demostrativo, y usuarios/productos/cotizaciones/métricas usan datos de demostración en varias vistas.

Este directorio incluye ejemplos de integración, no una edición automática del frontend completo. No se modificó tu repo GitHub y no se conectaron todas las páginas; para hacer una modificación reproducible de toda la web se necesita trabajar sobre un ZIP/branch actualizado de Angular.

## Secuencia para reemplazar el modo demo

1. Añade `environment.apiUrl` con la URL de API Gateway de tu stage, sin barra final.
2. Integra `auth.service.ts` y `api.interceptor.ts` en `appConfig.ts` junto con `provideHttpClient(withInterceptors([...]))`.
3. Actualiza el login para llamar `AuthService.login`; usa el rol devuelto por el API y navega al panel correspondiente.
4. Actualiza registro/confirmación/recuperación para invocar los endpoints que aparecen en `API_CONTRACT.md`.
5. Implementa guards UX con `auth.guard.ts`. La autorización real sigue en Lambda/SQL.
6. Sustituye cada consulta de `DemoDataService` por métodos de `api.service.ts` o llamadas HTTP equivalentes.
7. Cambia las rutas de detalle para incluir `:quoteCode`, por ejemplo `/admin/cotizaciones/detalle/:quoteCode`, y carga los datos de API.
8. En listados, muestra `itemCount` ya que el endpoint de lista no devuelve todo el array `items`.
9. PDF/impresión se resuelve en el frontend. El correo se envía con el endpoint de SES y requiere configurar su remitente.
10. Extiende `UserStatus` en `src/app/models/domain.ts` para incluir `Pendiente`, porque la API puede listar cuentas que aún no han confirmado el correo.
11. Cambia el contador de productos de una cotización para usar `quote.itemCount ?? quote.items.length`; el endpoint de lista no trae el detalle completo.
12. Ejecuta pruebas manuales por rol, especialmente cliente A tratando de leer una cotización del cliente B.

## Seguridad del almacenamiento de token

Los ejemplos usan `sessionStorage` como concesión para un proyecto académico SPA; es accesible por JavaScript y no elimina el riesgo XSS. Mantén Angular actualizado, evita HTML inseguro y no guardes credenciales de usuario. Para una aplicación productiva, considera Cognito Managed Login con Authorization Code + PKCE y un diseño de sesión más seguro (BFF/cookies HttpOnly según arquitectura). Para la entrega del manual se prioriza el flujo con formularios personalizados.
