/*
  Sistema de Cotizaciones - migracion para el esquema base entregado anteriormente.
  Ejecutar en db-cotizaciones, con copia de seguridad previa.
  Version corregida: separa los ALTER TABLE de los UPDATE/indices mediante GO,
  para evitar errores de compilacion por columnas agregadas en el mismo lote.
  Puede volver a ejecutarse si ya se aplicaron parcialmente las etapas anteriores.
*/
SET NOCOUNT ON;
GO

-- 1) Validar las tablas que debio crear 00_base_schema_for_empty_db.sql
IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL OR OBJECT_ID(N'dbo.Users', N'U') IS NULL OR
   OBJECT_ID(N'dbo.Customers', N'U') IS NULL OR OBJECT_ID(N'dbo.Products', N'U') IS NULL OR
   OBJECT_ID(N'dbo.Quotes', N'U') IS NULL OR OBJECT_ID(N'dbo.QuoteItems', N'U') IS NULL OR
   OBJECT_ID(N'dbo.QuoteStatusHistory', N'U') IS NULL
BEGIN
    THROW 51000, 'Falta una o mas tablas base. Ejecuta sql/90_check_schema.sql y revisa la base seleccionada.', 1;
END;
GO

-- 2) Asegurar los roles internos
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Code='ADMIN')
    INSERT dbo.Roles(Code, Name) VALUES ('ADMIN', N'Administrador');
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Code='SELLER')
    INSERT dbo.Roles(Code, Name) VALUES ('SELLER', N'Vendedor');
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Code='CUSTOMER')
    INSERT dbo.Roles(Code, Name) VALUES ('CUSTOMER', N'Cliente');
GO

-- 3) Agregar primero las columnas; no referenciarlas en este mismo lote
IF COL_LENGTH(N'dbo.Users', N'CognitoSub') IS NULL
    ALTER TABLE dbo.Users ADD CognitoSub NVARCHAR(64) NULL;
IF COL_LENGTH(N'dbo.Users', N'Phone') IS NULL
    ALTER TABLE dbo.Users ADD Phone NVARCHAR(40) NULL;
IF COL_LENGTH(N'dbo.Users', N'Notes') IS NULL
    ALTER TABLE dbo.Users ADD Notes NVARCHAR(1000) NULL;
IF COL_LENGTH(N'dbo.Users', N'StatusCode') IS NULL
    ALTER TABLE dbo.Users ADD StatusCode VARCHAR(20) NULL;
GO

-- 4) Completar el nuevo estado solo donde aun no tiene valor
UPDATE dbo.Users
SET StatusCode = CASE WHEN IsActive = 1 THEN 'ACTIVE' ELSE 'BLOCKED' END
WHERE StatusCode IS NULL;
GO

-- 5) Convertir estado a NOT NULL y agregar un DEFAULT si no existe
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Users')
      AND name = N'StatusCode' AND is_nullable = 1
)
    ALTER TABLE dbo.Users ALTER COLUMN StatusCode VARCHAR(20) NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.Users') AND c.name = N'StatusCode'
)
    ALTER TABLE dbo.Users ADD CONSTRAINT DF_Users_StatusCode_Upgrade DEFAULT ('ACTIVE') FOR StatusCode;
GO

-- PasswordHash queda NULL porque Cognito gestiona las contrasenas; nunca guardar texto plano.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Users') AND name = N'PasswordHash' AND is_nullable = 0
)
    ALTER TABLE dbo.Users ALTER COLUMN PasswordHash NVARCHAR(255) NULL;
GO

-- 6) Crear el indice despues de confirmar que CognitoSub ya existe
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_Users_CognitoSub' AND object_id = OBJECT_ID(N'dbo.Users')
)
    CREATE UNIQUE INDEX UX_Users_CognitoSub ON dbo.Users(CognitoSub) WHERE CognitoSub IS NOT NULL;
GO

-- 7) Extender productos
IF COL_LENGTH(N'dbo.Products', N'Slug') IS NULL
    ALTER TABLE dbo.Products ADD Slug VARCHAR(80) NULL;
IF COL_LENGTH(N'dbo.Products', N'Category') IS NULL
    ALTER TABLE dbo.Products ADD Category NVARCHAR(100) NULL;
IF COL_LENGTH(N'dbo.Products', N'Currency') IS NULL
    ALTER TABLE dbo.Products ADD Currency CHAR(3) NOT NULL CONSTRAINT DF_Products_Currency_Upgrade DEFAULT ('USD');
GO

UPDATE dbo.Products
SET Slug = 'product-' + CONVERT(VARCHAR(10), ProductId)
WHERE Slug IS NULL OR LTRIM(RTRIM(Slug)) = '';
UPDATE dbo.Products
SET Category = CASE WHEN ProductType = 'P' THEN N'Productos' ELSE N'Servicios' END
WHERE Category IS NULL OR LTRIM(RTRIM(Category)) = '';
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Products') AND name = N'Slug' AND is_nullable = 1
)
    ALTER TABLE dbo.Products ALTER COLUMN Slug VARCHAR(80) NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_Products_Slug' AND object_id = OBJECT_ID(N'dbo.Products')
)
    CREATE UNIQUE INDEX UX_Products_Slug ON dbo.Products(Slug);
GO

-- 8) Extender los snapshots de detalle de cotizacion
IF COL_LENGTH(N'dbo.QuoteItems', N'ProductSlugSnapshot') IS NULL
    ALTER TABLE dbo.QuoteItems ADD ProductSlugSnapshot VARCHAR(80) NULL;
IF COL_LENGTH(N'dbo.QuoteItems', N'DescriptionSnapshot') IS NULL
    ALTER TABLE dbo.QuoteItems ADD DescriptionSnapshot NVARCHAR(1000) NULL;
GO

UPDATE I
SET ProductSlugSnapshot = P.Slug,
    DescriptionSnapshot = P.Description
FROM dbo.QuoteItems AS I
JOIN dbo.Products AS P ON P.ProductId = I.ProductId
WHERE I.ProductSlugSnapshot IS NULL;

UPDATE dbo.QuoteItems
SET ProductSlugSnapshot = 'product-legacy'
WHERE ProductSlugSnapshot IS NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.QuoteItems')
      AND name = N'ProductSlugSnapshot' AND is_nullable = 1
)
    ALTER TABLE dbo.QuoteItems ALTER COLUMN ProductSlugSnapshot VARCHAR(80) NOT NULL;
GO

-- 9) Restricciones del estado, despues de crear la columna
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_Users_StatusCode_Upgrade'
      AND parent_object_id = OBJECT_ID(N'dbo.Users')
)
    ALTER TABLE dbo.Users ADD CONSTRAINT CK_Users_StatusCode_Upgrade
        CHECK (StatusCode IN ('PENDING', 'ACTIVE', 'BLOCKED'));
GO

-- 10) Verificacion final
SELECT DB_NAME() AS DatabaseName;
SELECT name FROM sys.tables
WHERE name IN ('Roles','Users','Customers','Products','Quotes','QuoteItems','QuoteStatusHistory')
ORDER BY name;
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Users','Products','QuoteItems')
  AND COLUMN_NAME IN ('CognitoSub','StatusCode','Phone','Notes','Slug','Category','Currency','ProductSlugSnapshot','DescriptionSnapshot')
ORDER BY TABLE_NAME, ORDINAL_POSITION;
GO
