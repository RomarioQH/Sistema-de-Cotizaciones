# Sistema de Cotizaciones — backend integral (AWS Lambda + SQL Server)

Este paquete amplía el backend inicial para cubrir la mayor parte de las operaciones que necesita el frontend Angular actual. Mantiene la arquitectura del manual de clase:

**Angular → API Gateway REST → funciones Lambda (Python 3.13 + pyodbc) → Amazon RDS for SQL Server.**

Amazon Cognito administra las credenciales y tokens; SQL Server conserva perfil, rol, catálogo, cotizaciones e historial. Amazon SES es opcional para enviar una cotización por correo.

> **Estado real:** el código fue revisado y compilado sintácticamente; no se ha desplegado ni probado contra tu cuenta AWS/RDS real. El frontend existente continúa usando `DemoDataService` en varias pantallas. Este paquete no modifica automáticamente tu repo Angular ni convierte por sí solo esas pantallas a API. Consulta `frontend-integration/README.md`.

## Muy importante antes de ejecutar SQL

Este paquete se ha adaptado al esquema del **backend inicial entregado antes** (`Roles`, `Users`, `Customers`, `Products`, `Quotes`, `QuoteItems`, `QuoteStatusHistory`). En tu caso, probablemente ya ejecutaste parte de ese esquema en `db-cotizaciones`.

1. Conéctate a **`db-cotizaciones`**, nunca a `rdsadmin`.
2. Haz una copia de seguridad / snapshot antes de cambiar la estructura.
3. Inspecciona las tablas usando `sql/90_check_schema.sql`.
4. Si las tablas anteriores ya existen, **no ejecutes** `00_base_schema_for_empty_db.sql`. Ejecuta `01_upgrade_existing_schema.sql`, después `02_seed_products.sql` y `03_procedures.sql`.
5. Ejecuta `04_bootstrap_admin.sql` solamente después de registrar y confirmar en Cognito tu propio usuario, y de cambiar el correo de reemplazo dentro del archivo.
6. Si no hay tablas y la base está vacía, ejecuta en orden `00_base_schema_for_empty_db.sql`, `01_upgrade_existing_schema.sql`, `02_seed_products.sql`, `03_procedures.sql`. No uses el esquema base sobre una base con datos sin una revisión manual.

Los scripts del manual del profesor que crean `TM_PROYECTO` o `TM_DEPARTAMENTO` son para el ejemplo inmobiliario, no para el dominio de esta web.

## Carpetas

- `lambda_src/`: handlers. Cada módulo se despliega como una función Lambda independiente.
- `sql/`: esquema, migración, catálogo inicial, procedimientos y comprobación.
- `dist/lambda-code.zip`: todos los módulos Python colocados en la raíz del ZIP, para subirlos a Lambda.
- `frontend-integration/`: contrato HTTP y ejemplos Angular para sustituir las llamadas simuladas.
- `policies/`: ejemplo de permisos IAM para Cognito y SES; sustituye los marcadores antes de usarlo.

## Base de datos: credenciales y conectividad

Crea un usuario de aplicación SQL Server separado del usuario master de RDS (por ejemplo `app_cotizaciones`). Ejecuta los scripts de estructura/procedimientos con un usuario que tenga permisos DDL; no uses el usuario master como credencial normal de Lambda. Concede a la cuenta de ejecución únicamente permisos `EXECUTE` sobre los procedimientos requeridos, más lo que realmente necesites. Mantén el endpoint privado y no abras TCP 1433 a `0.0.0.0/0`.

Configuración usada por `lambda_src/db.py`:

- `DB_SERVER`: solo el hostname del endpoint RDS, sin `tcp:` ni puerto.
- `DB_PORT`: normalmente `1433`.
- `DB_NAME`: `db-cotizaciones`.
- `DB_USER`: usuario SQL de aplicación.
- `DB_PASSWORD`: contraseña SQL. No la subas a GitHub. Para una entrega real conviene moverla a AWS Secrets Manager y adaptar la lectura del secreto.
- `COGNITO_USER_POOL_ID`: User Pool ID.
- `COGNITO_USER_POOL_CLIENT_ID`: App Client ID **sin client secret**.
- `AWS_REGION`: región en la que creaste RDS/Cognito/Lambda. En Lambda AWS define esta variable automáticamente; no intentes crearla manualmente allí. En `.env.example` sirve para pruebas locales.
- `ALLOWED_ORIGIN`: origen exacto de Angular, por ejemplo `http://localhost:4200` durante desarrollo o el dominio real del frontend.
- `SES_FROM_EMAIL`: correo remitente verificado, solo para la función de envío.

No copies los valores de `.env.example` tal cual; son marcadores.

## Capa Python / ODBC

Tus funciones que importan `db.py` necesitan una capa compatible con **Python 3.13 y arquitectura x86_64**, con `pyodbc`, Microsoft ODBC Driver 18 y sus bibliotecas del sistema (`unixODBC`). Añade la capa a cada función que necesite base de datos. `boto3` se usa para Cognito/SES y normalmente está disponible en el runtime; si empaquetas una versión propia, incluye sus dependencias compatibles.

El ZIP de código tiene módulos en raíz. Por ejemplo:

- `health_check.lambda_handler`
- `auth_register.lambda_handler`
- `auth_login.lambda_handler`
- `quotes_create.lambda_handler`

Para cada función crea una Lambda Python 3.13 x86_64, sube el mismo ZIP, selecciona el handler exacto y configura las variables de entorno. Como punto de partida usa memoria de 512 MB y timeout de 15–30 s; monitoriza métricas/logs y ajusta según pruebas.

## Rol de ejecución

Tu cuenta personal no reutiliza `LABROLE` de AWS Academy. Crea un rol de ejecución propio con `AWSLambdaBasicExecutionRole`. Añade permisos de Cognito únicamente a las acciones que usa el backend y restringidos al ARN de tu User Pool. La función `quotes_send` necesita `ses:SendEmail` restringido a la identidad remitente verificada. Si conectas Lambda a una VPC, necesita las capacidades de interfaz de red que corresponden a Lambda VPC.

Revisa `policies/lambda-cognito-ses-policy.template.json`. Sustituye los marcadores y revisa el mínimo privilegio antes de asociarla.

## Red VPC: punto que suele bloquear esta arquitectura

RDS SQL Server debe aceptar TCP 1433 **desde el grupo de seguridad de Lambda**, no desde todo Internet. Lambda y RDS normalmente estarán en la misma VPC. Configura el security group de RDS con origen el SG de Lambda.

Cuando colocas Lambda dentro de la VPC, no obtiene automáticamente salida a los endpoints públicos. Las funciones de registro/inicio de sesión llaman a Cognito; el envío llama a SES. Para que estas llamadas funcionen debes elegir una solución de salida:

- NAT Gateway (operativamente simple, pero puede tener coste constante importante), o
- VPC endpoints privados compatibles y configurados para las llamadas SDK que uses, verificando las limitaciones de Cognito User Pools (un endpoint privado de Cognito no sirve para flujos de dominio/Hosted UI), o
- rediseñar el flujo para que las llamadas a Cognito/SES sucedan fuera de la VPC y se coordinen con las operaciones que requieren RDS.

No des por hecho que una Lambda en subred privada podrá llamar Cognito o SES. Para mantener bajo el coste de un proyecto académico, primero estima costes de NAT/VPC endpoints y verifica qué servicios soporta la región elegida. No despliegues un NAT Gateway sin revisar presupuesto.

## Cognito: configuración necesaria

1. Crea un User Pool regional y usa el correo como opción de inicio de sesión.
2. Habilita verificación del correo y crea una política de contraseña apropiada.
3. Crea un App Client para SPA **sin client secret**.
4. Habilita los flujos `ALLOW_USER_PASSWORD_AUTH` y `ALLOW_REFRESH_TOKEN_AUTH` porque los handlers los usan.
5. Guarda User Pool ID y App Client ID en la configuración Lambda.
6. No concedas rol `ADMIN` desde el formulario público de registro. El registro público solo crea clientes (`CUSTOMER`). Para elevar tu cuenta inicial a administrador, usa el script `04_bootstrap_admin.sql` con tu correo confirmado.
7. La función `auth_complete_challenge` permite completar el cambio de contraseña que Cognito exige a usuarios invitados por administración.

## API Gateway REST API

Crea una REST API con integración Lambda Proxy para cada ruta de `frontend-integration/API_CONTRACT.md`. Configura las rutas de autenticación de baja confianza (register, login, confirmación, recuperación, refresh y challenge) como públicas. Protege las rutas privadas mediante un authorizer de Cognito User Pool.

Para una REST API Cognito User Pool authorizer sin OAuth scopes, envía el **ID token** en `Authorization: Bearer <idToken>`. El Lambda usa `sub` del authorizer para identificar la cuenta en SQL y vuelve a comprobar rol/estado en la base. El Access Token se conserva para operaciones Cognito como `GlobalSignOut` y se manda en el cuerpo del logout.

Configura CORS en API Gateway para el origen de Angular, cabeceras `Content-Type,Authorization` y métodos usados. En Lambda se incluye respuesta a `OPTIONS`, pero también debes habilitar las respuestas preflight en la API Gateway REST API (o crear métodos OPTIONS según el modo que elijas).

## Funciones y handlers

| Función sugerida | Handler | Ruta |
|---|---|---|
| `cotizaciones-health` | `health_check.lambda_handler` | `GET /health` |
| `cotizaciones-auth-register` | `auth_register.lambda_handler` | `POST /auth/register` |
| `cotizaciones-auth-login` | `auth_login.lambda_handler` | `POST /auth/login` |
| `cotizaciones-auth-confirm` | `auth_confirm_registration.lambda_handler` | `POST /auth/confirm-registration` |
| `cotizaciones-auth-forgot` | `auth_forgot_password.lambda_handler` | `POST /auth/forgot-password` |
| `cotizaciones-auth-reset` | `auth_confirm_password.lambda_handler` | `POST /auth/confirm-password` |
| `cotizaciones-auth-challenge` | `auth_complete_challenge.lambda_handler` | `POST /auth/complete-new-password` |
| `cotizaciones-auth-refresh` | `auth_refresh.lambda_handler` | `POST /auth/refresh` |
| `cotizaciones-auth-me` | `auth_me.lambda_handler` | `GET /auth/me` |
| `cotizaciones-auth-logout` | `auth_logout.lambda_handler` | `POST /auth/logout` |
| `cotizaciones-products-list` | `products_list.lambda_handler` | `GET /productos` |
| `cotizaciones-products-get` | `products_get.lambda_handler` | `GET /productos/{productId}` |
| `cotizaciones-users-list` | `users_list.lambda_handler` | `GET /usuarios` |
| `cotizaciones-users-create` | `users_create.lambda_handler` | `POST /usuarios` |
| `cotizaciones-users-update` | `users_update.lambda_handler` | `PATCH /usuarios/{userId}` |
| `cotizaciones-quotes-list` | `quotes_list.lambda_handler` | `GET /cotizaciones` |
| `cotizaciones-quotes-get` | `quotes_get.lambda_handler` | `GET /cotizaciones/{quoteCode}` |
| `cotizaciones-quotes-create` | `quotes_create.lambda_handler` | `POST /cotizaciones` |
| `cotizaciones-quotes-status` | `quotes_status.lambda_handler` | `PATCH /cotizaciones/{quoteCode}/estado` |
| `cotizaciones-quotes-send` | `quotes_send.lambda_handler` | `POST /cotizaciones/{quoteCode}/enviar` |
| `cotizaciones-dashboard-admin` | `dashboard_admin.lambda_handler` | `GET /dashboard/admin` |
| `cotizaciones-dashboard-vendor` | `dashboard_vendor.lambda_handler` | `GET /dashboard/vendedor` |
| `cotizaciones-dashboard-client` | `dashboard_client.lambda_handler` | `GET /dashboard/cliente` |
| `cotizaciones-reports` | `reports_admin.lambda_handler` | `GET /reportes` |

Puedes reutilizar el mismo ZIP para todas las funciones. No todas necesitan las mismas variables/permisos, pero todas las funciones que importan `db.py` requieren la capa ODBC y conectividad a RDS.

## Pruebas antes de publicar

1. Prueba `GET /health` usando el invoke test de Lambda con un evento mínimo. Respuesta esperada: `isSuccess=true`, `data.databaseConnected=true`.
2. Registra una cuenta, confirma el correo, inicia sesión, eleva solamente tu cuenta a `ADMIN` con el script de bootstrap y vuelve a iniciar sesión.
3. Lista el catálogo, crea una cotización, recupérala por su código, y verifica los totales desde SQL Server.
4. Prueba que un cliente no pueda leer cotizaciones de otro cliente, que vendedor no pueda ver las asignadas a otro vendedor y que los endpoints administrativos den `403` a roles no permitidos.
5. Verifica logs, límites, costes, manejo de CORS y los errores de red/credenciales antes de conectar Angular.

El endpoint de email requiere SES habilitado para tu cuenta, remitente verificado y permiso IAM. El PDF/impresión no se genera en Lambda actualmente: se termina desde la interfaz Angular (imprimir navegador o implementar una librería PDF en el frontend/backend).

## Funcionalidades no cubiertas automáticamente

- La integración en cada componente Angular actual todavía debe hacerse: reemplazar `DemoDataService`, conectar formularios, guards/interceptor, cargar rutas de detalle por `quoteCode` y tratar errores/loading/empty state.
- PDF de salida formal, plantillas de correo HTML con PDF adjunto, auditoría más avanzada, paginación, exportación Excel/CSV, gestión completa de catálogo y borrado lógico no están cerrados en este paquete.
- No se ha hecho una prueba de extremo a extremo con tu VPC, RDS, Cognito, SES o API Gateway reales.
