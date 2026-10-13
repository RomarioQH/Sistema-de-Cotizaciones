# Contrato de API para Angular

Base URL: `environment.apiUrl` (por ejemplo la URL `execute-api` de tu API Gateway REST). Todas las respuestas exitosas tienen forma `{ "isSuccess": true, "data": ... }`. Errores tienen `{ "isSuccess": false, "errorMessage": "..." }`.

Para las rutas protegidas, envía `Authorization: Bearer <idToken>` cuando el Cognito User Pool authorizer de API Gateway está configurado sin OAuth scopes. El `idToken` se obtiene del endpoint de login. Conserva el `accessToken` separado para `POST /auth/logout` y el `refreshToken` para renovar sesión.

## Autenticación (públicas, salvo `/auth/me` y `/auth/logout`)

| Método y ruta | Body | Uso |
|---|---|---|
| `GET /health` | — | Verificación de conexión a DB |
| `POST /auth/register` | `{name,email,password,phone?,company?}` | Registro; siempre crea cliente, nunca admin |
| `POST /auth/confirm-registration` | `{email,code}` | Confirmar código Cognito y activar perfil SQL |
| `POST /auth/login` | `{email,password}` | Devuelve `{accessToken,idToken,refreshToken,expiresIn,user}` o un challenge |
| `POST /auth/complete-new-password` | `{username,session,newPassword}` | Usuario invitado con `NEW_PASSWORD_REQUIRED` |
| `POST /auth/forgot-password` | `{email}` | Solicitar código para restablecer contraseña |
| `POST /auth/confirm-password` | `{email,code,newPassword}` | Establecer nueva contraseña |
| `POST /auth/refresh` | `{refreshToken}` | Renovar ID y access token |
| `GET /auth/me` | — | Perfil del usuario autenticado; protegida |
| `POST /auth/logout` | `{accessToken}` | Revocar sesión global Cognito y limpiar tokens locales; protege la ruta si lo configuras así |

## Catálogo y usuarios

| Método y ruta | Permiso |
|---|---|
| `GET /productos?search=&category=` | Usuario activo autenticado |
| `GET /productos/{productId}` | Usuario activo autenticado; `{productId}` es el slug, por ejemplo `web` |
| `GET /usuarios?search=` | Solo ADMIN |
| `POST /usuarios` | Solo ADMIN; body `{name,email,role:'vendedor'|'cliente',phone?,company?}` |
| `PATCH /usuarios/{userId}` | Solo ADMIN; body `{name,role,status,phone?,company?,notes?}`; no permite crear/editar ADMIN por API |

## Cotizaciones

| Método y ruta | Permiso |
|---|---|
| `GET /cotizaciones?search=&status=` | Filtra por rol automáticamente; admin ve todas, vendedor las asignadas, cliente las propias |
| `GET /cotizaciones/{quoteCode}` | Solo si el rol tiene acceso a esa cotización |
| `POST /cotizaciones` | Usuario autenticado; el servidor recalcula importes y no confía en los totales del navegador |
| `PATCH /cotizaciones/{quoteCode}/estado` | Cliente puede aceptar/rechazar una enviada; vendedor/admin pueden enviar un borrador según reglas de SQL |
| `POST /cotizaciones/{quoteCode}/enviar` | Solo ADMIN o SELLER; requiere Amazon SES configurado |

Body de crear cotización:

```json
{
  "items": [
    { "productId": "web", "quantity": 1 },
    { "productId": "crm", "quantity": 2 }
  ],
  "discountPercent": 0,
  "taxPercent": 18,
  "customerMessage": "Alcance y condiciones"
}
```

Para CLIENTE, el backend ignora un `customerId` enviado por el navegador y usa la identidad autenticada. Para ADMIN/SELLER, `customerId` debe ser el `Users.UserId` del cliente; para asignar un vendedor al crear con ADMIN se puede enviar `sellerId`. No se debe enviar precio unitario ni total como fuente de verdad; el SQL toma los precios activos del catálogo y calcula los importes.

Los estados externos son `Borrador`, `Enviada`, `Aceptada`, `Rechazada`; internamente SQL usa `DRAFT`, `PENDING`, `APPROVED`, `OBSERVED`. Los ids de cotización son códigos `COT-00000001`; los ids de productos son slugs (`web`, `mobile`, `crm`, `ecommerce`). Las respuestas de lista incluyen `itemCount` y `items: []`; el Angular debe usar `itemCount` en la tabla, y pedir `GET /cotizaciones/{quoteCode}` para cargar ítems/historial del detalle.

## Dashboards y reportes

| Método y ruta | Permiso |
|---|---|
| `GET /dashboard/admin` | ADMIN |
| `GET /dashboard/vendedor` | SELLER |
| `GET /dashboard/cliente` | CUSTOMER |
| `GET /reportes` | ADMIN |

## Reglas de integración del frontend existente

- `admin`, `vendedor`, `cliente` son los roles de Angular. No son una decisión confiable del navegador; la API devuelve el rol de SQL después de validar `sub` de Cognito.
- Reemplaza `DemoDataService.authenticate()` y los arreglos en memoria por `AuthService`/`HttpClient`.
- El alta no debe navegar directamente al panel: espera la respuesta API y muestra paso de confirmación.
- La recuperación debe llamar las dos rutas de recuperación reales.
- Protege rutas Angular con guards para UX, pero considera al API Gateway/Lambda/SQL como autoridad real de autorización.
- Los paneles/reportes se cargan desde sus endpoints, no de cifras fijas.
- En cotizaciones, abre el detalle con el `quoteCode`, no con un id numérico interno.
- El PDF y la impresión no se implementan en estos handlers; el frontend debe generar la vista imprimible/PDF. El botón de correo usa `/cotizaciones/{quoteCode}/enviar`.
