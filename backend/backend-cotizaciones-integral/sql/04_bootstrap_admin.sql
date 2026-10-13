/*
  OPCIONAL: elevar a administrador una cuenta que YA se registró y confirmó correo en Cognito.
  Cambia el correo de reemplazo. Ejecuta solo después de confirmar que es tu propia cuenta.
  No crea identidad en Cognito; solo sincroniza el rol SQL con esa identidad.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
DECLARE @AdminEmail NVARCHAR(254) = LOWER(N'REPLACE_WITH_YOUR_CONFIRMED_EMAIL');
IF @AdminEmail = N'replace_with_your_confirmed_email'
    THROW 53001, 'Edita @AdminEmail con el correo de tu cuenta confirmada antes de ejecutar.', 1;
DECLARE @AdminRoleId INT = (SELECT RoleId FROM dbo.Roles WHERE Code='ADMIN');
IF @AdminRoleId IS NULL THROW 53002, 'Falta el rol ADMIN. Ejecuta sql/01_upgrade_existing_schema.sql.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Email=@AdminEmail AND CognitoSub IS NOT NULL AND StatusCode='ACTIVE' AND IsActive=1)
    THROW 53003, 'No existe un perfil ACTIVO y confirmado para ese correo. Registra y confirma primero la cuenta.', 1;
BEGIN TRANSACTION;
UPDATE dbo.Users SET RoleId=@AdminRoleId, IsActive=1, StatusCode='ACTIVE', UpdatedAt=SYSUTCDATETIME() WHERE Email=@AdminEmail;
UPDATE C SET IsActive=0, UpdatedAt=SYSUTCDATETIME() FROM dbo.Customers C JOIN dbo.Users U ON U.UserId=C.UserId WHERE U.Email=@AdminEmail;
COMMIT;
SELECT U.UserId,U.Email,R.Code AS RoleCode,U.StatusCode,U.IsActive
FROM dbo.Users U JOIN dbo.Roles R ON R.RoleId=U.RoleId WHERE U.Email=@AdminEmail;
GO
