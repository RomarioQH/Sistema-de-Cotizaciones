/*
  Sistema de Cotizaciones - SQL Server (Amazon RDS)
  Ejecutar conectado a la base de datos destino, NO en master.
  Script idempotente para tablas: solo crea objetos que todavía no existen.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Roles
    (
        RoleId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
        Code         VARCHAR(20) NOT NULL,
        Name         NVARCHAR(80) NOT NULL,
        IsActive     BIT NOT NULL CONSTRAINT DF_Roles_IsActive DEFAULT (1),
        CreatedAt    DATETIME2(0) NOT NULL CONSTRAINT DF_Roles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_Roles_Code UNIQUE (Code)
    );
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        UserId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
        RoleId           INT NOT NULL,
        Email            NVARCHAR(254) NOT NULL,
        PasswordHash     NVARCHAR(255) NOT NULL,
        FirstName        NVARCHAR(100) NOT NULL,
        LastName         NVARCHAR(100) NOT NULL,
        IsActive         BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
        CreatedAt        DATETIME2(0) NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2(0) NULL,
        CreatedByUserId  INT NULL,
        CONSTRAINT UQ_Users_Email UNIQUE (Email),
        CONSTRAINT FK_Users_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(RoleId),
        CONSTRAINT FK_Users_CreatedBy FOREIGN KEY (CreatedByUserId) REFERENCES dbo.Users(UserId)
    );
END;
GO

IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers
    (
        CustomerId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
        UserId        INT NOT NULL,
        CompanyName   NVARCHAR(180) NOT NULL,
        TaxId         VARCHAR(11) NULL,
        ContactName   NVARCHAR(180) NULL,
        Phone         NVARCHAR(30) NULL,
        IsActive      BIT NOT NULL CONSTRAINT DF_Customers_IsActive DEFAULT (1),
        CreatedAt     DATETIME2(0) NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt     DATETIME2(0) NULL,
        CONSTRAINT UQ_Customers_UserId UNIQUE (UserId),
        CONSTRAINT FK_Customers_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_Customers_TaxId CHECK (TaxId IS NULL OR LEN(TaxId) = 11)
    );
END;
GO

IF OBJECT_ID(N'dbo.Products', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Products
    (
        ProductId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
        SKU              NVARCHAR(50) NOT NULL,
        Name             NVARCHAR(200) NOT NULL,
        Description      NVARCHAR(1000) NULL,
        ProductType      CHAR(1) NOT NULL, -- P = producto, S = servicio
        UnitPrice        DECIMAL(12,2) NOT NULL,
        IsStockManaged   BIT NOT NULL CONSTRAINT DF_Products_IsStockManaged DEFAULT (0),
        StockQuantity    INT NULL,
        IsActive         BIT NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1),
        CreatedAt        DATETIME2(0) NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2(0) NULL,
        CreatedByUserId  INT NULL,
        CONSTRAINT UQ_Products_SKU UNIQUE (SKU),
        CONSTRAINT FK_Products_CreatedBy FOREIGN KEY (CreatedByUserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_Products_Type CHECK (ProductType IN ('P', 'S')),
        CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice >= 0),
        CONSTRAINT CK_Products_Stock CHECK (StockQuantity IS NULL OR StockQuantity >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.Quotes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Quotes
    (
        QuoteId              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Quotes PRIMARY KEY,
        QuoteCode            AS (CONVERT(NVARCHAR(30), N'COT-' + RIGHT('00000000' + CONVERT(VARCHAR(8), QuoteId), 8))) PERSISTED,
        CustomerId           INT NOT NULL,
        CreatedByUserId      INT NOT NULL,
        AssignedSellerUserId INT NULL,
        Status               VARCHAR(20) NOT NULL CONSTRAINT DF_Quotes_Status DEFAULT ('DRAFT'),
        DiscountPercent      DECIMAL(5,2) NOT NULL CONSTRAINT DF_Quotes_DiscountPercent DEFAULT (0),
        Subtotal             DECIMAL(14,2) NOT NULL CONSTRAINT DF_Quotes_Subtotal DEFAULT (0),
        DiscountAmount       DECIMAL(14,2) NOT NULL CONSTRAINT DF_Quotes_DiscountAmount DEFAULT (0),
        TaxRate              DECIMAL(5,4) NOT NULL CONSTRAINT DF_Quotes_TaxRate DEFAULT (0.1800),
        TaxAmount            DECIMAL(14,2) NOT NULL CONSTRAINT DF_Quotes_TaxAmount DEFAULT (0),
        Total                DECIMAL(14,2) NOT NULL CONSTRAINT DF_Quotes_Total DEFAULT (0),
        CustomerMessage      NVARCHAR(1000) NULL,
        ReviewComment        NVARCHAR(1000) NULL,
        CreatedAt            DATETIME2(0) NOT NULL CONSTRAINT DF_Quotes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2(0) NULL,
        SubmittedAt          DATETIME2(0) NULL,
        ReviewedAt           DATETIME2(0) NULL,
        CONSTRAINT UQ_Quotes_QuoteCode UNIQUE (QuoteCode),
        CONSTRAINT FK_Quotes_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
        CONSTRAINT FK_Quotes_CreatedBy FOREIGN KEY (CreatedByUserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_Quotes_AssignedSeller FOREIGN KEY (AssignedSellerUserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_Quotes_Status CHECK (Status IN ('DRAFT', 'PENDING', 'APPROVED', 'OBSERVED')),
        CONSTRAINT CK_Quotes_DiscountPercent CHECK (DiscountPercent >= 0 AND DiscountPercent <= 100),
        CONSTRAINT CK_Quotes_TaxRate CHECK (TaxRate >= 0 AND TaxRate <= 1),
        CONSTRAINT CK_Quotes_Amounts CHECK (Subtotal >= 0 AND DiscountAmount >= 0 AND TaxAmount >= 0 AND Total >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.QuoteItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.QuoteItems
    (
        QuoteItemId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_QuoteItems PRIMARY KEY,
        QuoteId           INT NOT NULL,
        ProductId         INT NOT NULL,
        ProductNameSnapshot NVARCHAR(200) NOT NULL,
        SKUSnapshot       NVARCHAR(50) NOT NULL,
        Quantity          DECIMAL(12,2) NOT NULL,
        UnitPriceAtQuote  DECIMAL(12,2) NOT NULL,
        LineSubtotal      AS (CONVERT(DECIMAL(14,2), Quantity * UnitPriceAtQuote)) PERSISTED,
        CreatedAt         DATETIME2(0) NOT NULL CONSTRAINT DF_QuoteItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_QuoteItems_Quotes FOREIGN KEY (QuoteId) REFERENCES dbo.Quotes(QuoteId),
        CONSTRAINT FK_QuoteItems_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId),
        CONSTRAINT UQ_QuoteItems_Quote_Product UNIQUE (QuoteId, ProductId),
        CONSTRAINT CK_QuoteItems_Quantity CHECK (Quantity > 0),
        CONSTRAINT CK_QuoteItems_UnitPrice CHECK (UnitPriceAtQuote >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.QuoteStatusHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.QuoteStatusHistory
    (
        HistoryId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_QuoteStatusHistory PRIMARY KEY,
        QuoteId         INT NOT NULL,
        PreviousStatus  VARCHAR(20) NULL,
        NewStatus       VARCHAR(20) NOT NULL,
        Comment         NVARCHAR(1000) NULL,
        ChangedByUserId INT NOT NULL,
        ChangedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_QuoteStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_QuoteStatusHistory_Quotes FOREIGN KEY (QuoteId) REFERENCES dbo.Quotes(QuoteId),
        CONSTRAINT FK_QuoteStatusHistory_Users FOREIGN KEY (ChangedByUserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_QuoteStatusHistory_NewStatus CHECK (NewStatus IN ('DRAFT', 'PENDING', 'APPROVED', 'OBSERVED')),
        CONSTRAINT CK_QuoteStatusHistory_PreviousStatus CHECK (PreviousStatus IS NULL OR PreviousStatus IN ('DRAFT', 'PENDING', 'APPROVED', 'OBSERVED'))
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Products_IsActive_Name' AND object_id = OBJECT_ID(N'dbo.Products'))
    CREATE INDEX IX_Products_IsActive_Name ON dbo.Products(IsActive, Name);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Quotes_Customer_CreatedAt' AND object_id = OBJECT_ID(N'dbo.Quotes'))
    CREATE INDEX IX_Quotes_Customer_CreatedAt ON dbo.Quotes(CustomerId, CreatedAt DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Quotes_Status_CreatedAt' AND object_id = OBJECT_ID(N'dbo.Quotes'))
    CREATE INDEX IX_Quotes_Status_CreatedAt ON dbo.Quotes(Status, CreatedAt DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_QuoteStatusHistory_Quote_ChangedAt' AND object_id = OBJECT_ID(N'dbo.QuoteStatusHistory'))
    CREATE INDEX IX_QuoteStatusHistory_Quote_ChangedAt ON dbo.QuoteStatusHistory(QuoteId, ChangedAt DESC);
GO
