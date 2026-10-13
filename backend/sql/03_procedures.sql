/* Procedures adapted to the schema used by backend-cotizaciones-rest-lambda starter.
   Internal roles: ADMIN/SELLER/CUSTOMER. Internal quote states: DRAFT/PENDING/APPROVED/OBSERVED. */
SET NOCOUNT ON;
GO
CREATE OR ALTER PROCEDURE dbo.usp_HealthCheck AS
BEGIN
 SET NOCOUNT ON; SELECT CAST(1 AS INT) AS databaseOk,DB_NAME() AS databaseName,SYSUTCDATETIME() AS serverUtcTime;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_RegisterPending
 @CognitoSub NVARCHAR(64),@FullName NVARCHAR(150),@Email NVARCHAR(254),@Phone NVARCHAR(40)=NULL,@CompanyName NVARCHAR(160)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF EXISTS(SELECT 1 FROM dbo.Users WHERE Email=LOWER(@Email) OR CognitoSub=@CognitoSub) THROW 52001,'Email o identidad ya registrados.',1;
 DECLARE @space INT=CHARINDEX(N' ',LTRIM(RTRIM(@FullName))),@first NVARCHAR(100),@last NVARCHAR(100),@userId INT;
 SET @first=CASE WHEN @space=0 THEN LEFT(LTRIM(RTRIM(@FullName)),100) ELSE LEFT(LTRIM(RTRIM(@FullName)),100) END;
 SET @last=CASE WHEN @space=0 THEN N'' ELSE LTRIM(SUBSTRING(LTRIM(RTRIM(@FullName)),@space+1,100)) END;
 BEGIN TRANSACTION;
 INSERT dbo.Users(RoleId,Email,PasswordHash,FirstName,LastName,IsActive,UpdatedAt,CreatedByUserId,CognitoSub,Phone,StatusCode,Notes)
 VALUES((SELECT RoleId FROM dbo.Roles WHERE Code='CUSTOMER'),LOWER(@Email),NULL,@first,@last,0,NULL,NULL,@CognitoSub,@Phone,'PENDING',NULL);
 SET @userId=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.Customers(UserId,CompanyName,TaxId,ContactName,Phone,IsActive,UpdatedAt)
 VALUES(@userId,COALESCE(NULLIF(@CompanyName,N''),@FullName),NULL,@FullName,@Phone,0,NULL);
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_ActivateByEmail @Email NVARCHAR(254)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
 UPDATE dbo.Users SET StatusCode='ACTIVE',IsActive=1,UpdatedAt=SYSUTCDATETIME() WHERE Email=LOWER(@Email) AND StatusCode='PENDING';
 IF @@ROWCOUNT=0 AND NOT EXISTS(SELECT 1 FROM dbo.Users WHERE Email=LOWER(@Email) AND StatusCode='ACTIVE') BEGIN ROLLBACK; THROW 52002,'Perfil pendiente no encontrado.',1; END;
 UPDATE C SET IsActive=1,UpdatedAt=SYSUTCDATETIME() FROM dbo.Customers C JOIN dbo.Users U ON U.UserId=C.UserId WHERE U.Email=LOWER(@Email) AND U.StatusCode='ACTIVE';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_GetBySub @CognitoSub NVARCHAR(64)
AS
BEGIN
 SET NOCOUNT ON;
 SELECT U.UserId AS userId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS name,U.Email AS email,
  COALESCE(U.Phone,C.Phone) AS phone,C.CompanyName AS companyName,R.Code AS roleCode,
  U.StatusCode AS statusCode,U.CreatedAt AS createdAt,U.Notes AS notes
 FROM dbo.Users U JOIN dbo.Roles R ON R.RoleId=U.RoleId LEFT JOIN dbo.Customers C ON C.UserId=U.UserId
 WHERE U.CognitoSub=@CognitoSub;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_GetById @UserId INT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT U.UserId AS userId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS name,U.Email AS email,
  COALESCE(U.Phone,C.Phone) AS phone,C.CompanyName AS companyName,R.Code AS roleCode,
  U.StatusCode AS statusCode,U.CreatedAt AS createdAt,U.Notes AS notes
 FROM dbo.Users U JOIN dbo.Roles R ON R.RoleId=U.RoleId LEFT JOIN dbo.Customers C ON C.UserId=U.UserId WHERE U.UserId=@UserId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_List @Search NVARCHAR(150)=NULL
AS
BEGIN
 SET NOCOUNT ON; DECLARE @s NVARCHAR(150)=NULLIF(LTRIM(RTRIM(@Search)),N'');
 SELECT U.UserId AS userId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS name,U.Email AS email,
  COALESCE(U.Phone,C.Phone) AS phone,C.CompanyName AS companyName,R.Code AS roleCode,U.StatusCode AS statusCode,
  U.CreatedAt AS createdAt,U.Notes AS notes
 FROM dbo.Users U JOIN dbo.Roles R ON R.RoleId=U.RoleId LEFT JOIN dbo.Customers C ON C.UserId=U.UserId
 WHERE @s IS NULL OR U.FirstName LIKE N'%'+@s+N'%' OR U.LastName LIKE N'%'+@s+N'%' OR U.Email LIKE N'%'+@s+N'%' OR C.CompanyName LIKE N'%'+@s+N'%'
 ORDER BY U.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_CreateInvited
 @CognitoSub NVARCHAR(64),@FullName NVARCHAR(150),@Email NVARCHAR(254),@Phone NVARCHAR(40)=NULL,
 @CompanyName NVARCHAR(160)=NULL,@RoleCode VARCHAR(20),@CreatedByUserId INT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @RoleCode NOT IN ('SELLER','CUSTOMER') THROW 52003,'Rol no permitido para alta administrativa.',1;
 IF EXISTS(SELECT 1 FROM dbo.Users WHERE Email=LOWER(@Email) OR CognitoSub=@CognitoSub) THROW 52004,'Email o identidad ya existe.',1;
 DECLARE @space INT=CHARINDEX(N' ',LTRIM(RTRIM(@FullName))),@first NVARCHAR(100),@last NVARCHAR(100),@userId INT;
 SET @first=LEFT(LTRIM(RTRIM(@FullName)),100);
 SET @last=CASE WHEN @space=0 THEN N'' ELSE LTRIM(SUBSTRING(LTRIM(RTRIM(@FullName)),@space+1,100)) END;
 BEGIN TRANSACTION;
 INSERT dbo.Users(RoleId,Email,PasswordHash,FirstName,LastName,IsActive,UpdatedAt,CreatedByUserId,CognitoSub,Phone,StatusCode)
 VALUES((SELECT RoleId FROM dbo.Roles WHERE Code=@RoleCode),LOWER(@Email),NULL,@first,@last,1,SYSUTCDATETIME(),@CreatedByUserId,@CognitoSub,@Phone,'ACTIVE');
 SET @userId=CONVERT(INT,SCOPE_IDENTITY());
 IF @RoleCode='CUSTOMER'
  INSERT dbo.Customers(UserId,CompanyName,TaxId,ContactName,Phone,IsActive,UpdatedAt) VALUES(@userId,COALESCE(NULLIF(@CompanyName,N''),@FullName),NULL,@FullName,@Phone,1,SYSUTCDATETIME());
 COMMIT;
 SELECT @userId AS userId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_User_Update
 @UserId INT,@FullName NVARCHAR(150),@Phone NVARCHAR(40)=NULL,@CompanyName NVARCHAR(160)=NULL,
 @RoleCode VARCHAR(20),@StatusCode VARCHAR(20),@Notes NVARCHAR(1000)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @RoleCode NOT IN ('CUSTOMER','SELLER') THROW 52005,'La API no permite asignar el rol administrador.',1;
 IF @StatusCode NOT IN ('PENDING','ACTIVE','BLOCKED') THROW 52006,'Estado inválido.',1;
 DECLARE @space INT=CHARINDEX(N' ',LTRIM(RTRIM(@FullName))),@first NVARCHAR(100),@last NVARCHAR(100),@oldRole VARCHAR(20);
 SET @first=LEFT(LTRIM(RTRIM(@FullName)),100); SET @last=CASE WHEN @space=0 THEN N'' ELSE LTRIM(SUBSTRING(LTRIM(RTRIM(@FullName)),@space+1,100)) END;
 SELECT @oldRole=R.Code FROM dbo.Users U JOIN dbo.Roles R ON R.RoleId=U.RoleId WHERE U.UserId=@UserId;
 IF @oldRole IS NULL OR @oldRole='ADMIN' THROW 52007,'Usuario no encontrado o no editable.',1;
 BEGIN TRANSACTION;
 UPDATE dbo.Users SET FirstName=@first,LastName=@last,Phone=@Phone,RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code=@RoleCode),
  IsActive=CASE WHEN @StatusCode='ACTIVE' THEN 1 ELSE 0 END,StatusCode=@StatusCode,Notes=@Notes,UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 IF @RoleCode='CUSTOMER'
 BEGIN
   IF EXISTS(SELECT 1 FROM dbo.Customers WHERE UserId=@UserId)
    UPDATE dbo.Customers SET CompanyName=COALESCE(NULLIF(@CompanyName,N''),@FullName),ContactName=@FullName,Phone=@Phone,IsActive=CASE WHEN @StatusCode='ACTIVE' THEN 1 ELSE 0 END,UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
   ELSE INSERT dbo.Customers(UserId,CompanyName,ContactName,Phone,IsActive,UpdatedAt) VALUES(@UserId,COALESCE(NULLIF(@CompanyName,N''),@FullName),@FullName,@Phone,CASE WHEN @StatusCode='ACTIVE' THEN 1 ELSE 0 END,SYSUTCDATETIME());
 END
 ELSE UPDATE dbo.Customers SET IsActive=0,UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 COMMIT;
 EXEC dbo.usp_User_GetById @UserId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Product_ListActive @Search NVARCHAR(120)=NULL,@Category NVARCHAR(100)=NULL
AS
BEGIN
 SET NOCOUNT ON; DECLARE @s NVARCHAR(120)=NULLIF(LTRIM(RTRIM(@Search)),N''),@cat NVARCHAR(100)=NULLIF(LTRIM(RTRIM(@Category)),N'');
 SELECT Slug AS id,SKU AS sku,Name AS title,Category AS category,Description AS description,UnitPrice AS price,Currency AS currency
 FROM dbo.Products WHERE IsActive=1 AND (@s IS NULL OR Name LIKE N'%'+@s+N'%' OR SKU LIKE N'%'+@s+N'%' OR Description LIKE N'%'+@s+N'%')
 AND (@cat IS NULL OR Category=@cat) ORDER BY Name;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Product_GetBySlug @Slug VARCHAR(80)
AS
BEGIN
 SET NOCOUNT ON;
 SELECT Slug AS id,SKU AS sku,Name AS title,Category AS category,Description AS description,UnitPrice AS price,Currency AS currency FROM dbo.Products WHERE Slug=@Slug AND IsActive=1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Quote_ListForActor @UserId INT,@RoleCode VARCHAR(20),@Search NVARCHAR(100)=NULL,@Status VARCHAR(20)=NULL
AS
BEGIN
 SET NOCOUNT ON; DECLARE @s NVARCHAR(100)=NULLIF(LTRIM(RTRIM(@Search)),N'');
 SELECT Q.QuoteCode AS quoteCode,C.UserId AS customerId,LTRIM(RTRIM(CONCAT(CU.FirstName,N' ',CU.LastName))) AS customerName,
  CU.Email AS customerEmail,COALESCE(CU.Phone,C.Phone) AS customerPhone,C.CompanyName AS customerCompany,
  Q.AssignedSellerUserId AS sellerId,LTRIM(RTRIM(CONCAT(S.FirstName,N' ',S.LastName))) AS sellerName,S.Email AS sellerEmail,
  Q.Status AS status,Q.DiscountPercent AS discountPercent,Q.TaxRate*100.0 AS taxPercent,Q.Subtotal AS subtotal,Q.DiscountAmount AS discountAmount,
  Q.TaxAmount AS taxAmount,Q.Total AS total,'USD' AS currency,Q.CustomerMessage AS customerMessage,Q.ReviewComment AS reviewComment,Q.CreatedAt AS createdAt,
  (SELECT COUNT(*) FROM dbo.QuoteItems I WHERE I.QuoteId=Q.QuoteId) AS itemCount
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId JOIN dbo.Users CU ON CU.UserId=C.UserId
 LEFT JOIN dbo.Users S ON S.UserId=Q.AssignedSellerUserId
 WHERE (@RoleCode='ADMIN' OR (@RoleCode='SELLER' AND Q.AssignedSellerUserId=@UserId) OR (@RoleCode='CUSTOMER' AND C.UserId=@UserId))
 AND (@s IS NULL OR Q.QuoteCode LIKE N'%'+@s+N'%' OR CU.FirstName LIKE N'%'+@s+N'%' OR CU.LastName LIKE N'%'+@s+N'%' OR C.CompanyName LIKE N'%'+@s+N'%')
 AND (@Status IS NULL OR Q.Status=@Status) ORDER BY Q.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Quote_GetByCode @QuoteCode NVARCHAR(30),@UserId INT,@RoleCode VARCHAR(20)
AS
BEGIN
 SET NOCOUNT ON;
 SELECT Q.QuoteId AS quoteId,Q.QuoteCode AS quoteCode,C.UserId AS customerId,LTRIM(RTRIM(CONCAT(CU.FirstName,N' ',CU.LastName))) AS customerName,
  CU.Email AS customerEmail,COALESCE(CU.Phone,C.Phone) AS customerPhone,C.CompanyName AS customerCompany,
  Q.AssignedSellerUserId AS sellerId,LTRIM(RTRIM(CONCAT(S.FirstName,N' ',S.LastName))) AS sellerName,S.Email AS sellerEmail,
  Q.Status AS status,Q.DiscountPercent AS discountPercent,Q.TaxRate*100.0 AS taxPercent,Q.Subtotal AS subtotal,Q.DiscountAmount AS discountAmount,
  Q.TaxAmount AS taxAmount,Q.Total AS total,'USD' AS currency,Q.CustomerMessage AS customerMessage,Q.ReviewComment AS reviewComment,
  Q.CreatedAt AS createdAt,Q.SubmittedAt AS sentAt,Q.ReviewedAt AS reviewedAt
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId JOIN dbo.Users CU ON CU.UserId=C.UserId
 LEFT JOIN dbo.Users S ON S.UserId=Q.AssignedSellerUserId
 WHERE Q.QuoteCode=@QuoteCode AND (@RoleCode='ADMIN' OR (@RoleCode='SELLER' AND Q.AssignedSellerUserId=@UserId) OR (@RoleCode='CUSTOMER' AND C.UserId=@UserId));
 IF @@ROWCOUNT=0 RETURN;
 DECLARE @id INT=(SELECT QuoteId FROM dbo.Quotes WHERE QuoteCode=@QuoteCode);
 SELECT I.ProductSlugSnapshot AS productId,I.ProductNameSnapshot AS title,I.DescriptionSnapshot AS description,
  I.Quantity AS quantity,I.UnitPriceAtQuote AS unitPrice,I.LineSubtotal AS lineSubtotal
 FROM dbo.QuoteItems I WHERE I.QuoteId=@id ORDER BY I.QuoteItemId;
 SELECT H.PreviousStatus AS previousStatus,H.NewStatus AS newStatus,H.Comment AS comment,H.ChangedAt AS changedAt,
  LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS changedByName
 FROM dbo.QuoteStatusHistory H JOIN dbo.Users U ON U.UserId=H.ChangedByUserId WHERE H.QuoteId=@id ORDER BY H.ChangedAt;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Quote_Create
 @ActorUserId INT,@RoleCode VARCHAR(20),@CustomerUserId INT=NULL,@AssignedSellerUserId INT=NULL,
 @DiscountPercent DECIMAL(5,2)=0,@TaxPercent DECIMAL(5,2)=18,@CustomerMessage NVARCHAR(1000)=NULL,@ItemsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @RoleCode NOT IN ('ADMIN','SELLER','CUSTOMER') THROW 52101,'Rol no permitido.',1;
 IF @DiscountPercent NOT BETWEEN 0 AND 100 OR @TaxPercent NOT BETWEEN 0 AND 100 THROW 52102,'Descuento o impuesto inválido.',1;
 IF @RoleCode='CUSTOMER' SET @CustomerUserId=@ActorUserId;
 DECLARE @CustomerId INT;
 SELECT @CustomerId=C.CustomerId FROM dbo.Customers C JOIN dbo.Users U ON U.UserId=C.UserId
 WHERE C.UserId=@CustomerUserId AND C.IsActive=1 AND U.IsActive=1 AND U.StatusCode='ACTIVE' AND U.RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code='CUSTOMER');
 IF @CustomerId IS NULL THROW 52103,'El cliente no existe o está inactivo.',1;
 IF @RoleCode='SELLER' SET @AssignedSellerUserId=@ActorUserId;
 IF @AssignedSellerUserId IS NULL
  SELECT TOP(1) @AssignedSellerUserId=U.UserId FROM dbo.Users U WHERE U.RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code='SELLER') AND U.IsActive=1 AND U.StatusCode='ACTIVE'
  ORDER BY (SELECT COUNT(*) FROM dbo.Quotes Q WHERE Q.AssignedSellerUserId=U.UserId AND Q.Status IN ('DRAFT','PENDING')) ASC,U.UserId;
 IF @AssignedSellerUserId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Users WHERE UserId=@AssignedSellerUserId AND RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code='SELLER') AND IsActive=1 AND StatusCode='ACTIVE')
  THROW 52104,'Vendedor asignado no válido.',1;
 IF ISJSON(@ItemsJson)<>1 THROW 52105,'ItemsJson inválido.',1;
 DECLARE @items TABLE(Slug VARCHAR(80) NOT NULL,Quantity DECIMAL(12,2) NOT NULL);
 INSERT @items(Slug,Quantity) SELECT ProductId,Quantity FROM OPENJSON(@ItemsJson) WITH(ProductId VARCHAR(80) '$.productId',Quantity DECIMAL(12,2) '$.quantity');
 IF NOT EXISTS(SELECT 1 FROM @items) OR EXISTS(SELECT 1 FROM @items WHERE Quantity<=0) THROW 52106,'Se requiere producto y cantidad positiva.',1;
 IF EXISTS(SELECT Slug FROM @items GROUP BY Slug HAVING COUNT(*)>1) THROW 52107,'Productos duplicados.',1;
 IF EXISTS(SELECT 1 FROM @items I LEFT JOIN dbo.Products P ON P.Slug=I.Slug AND P.IsActive=1 WHERE P.ProductId IS NULL) THROW 52108,'Producto inactivo o inexistente.',1;
 BEGIN TRANSACTION;
 DECLARE @subtotal DECIMAL(14,2),@discountAmount DECIMAL(14,2),@taxRate DECIMAL(5,4),@taxAmount DECIMAL(14,2),@total DECIMAL(14,2),@quoteId INT;
 SELECT @subtotal=CONVERT(DECIMAL(14,2),SUM(I.Quantity*P.UnitPrice)) FROM @items I JOIN dbo.Products P ON P.Slug=I.Slug;
 SET @discountAmount=ROUND(@subtotal*@DiscountPercent/100.0,2); SET @taxRate=@TaxPercent/100.0;
 SET @taxAmount=ROUND((@subtotal-@discountAmount)*@taxRate,2); SET @total=@subtotal-@discountAmount+@taxAmount;
 INSERT dbo.Quotes(CustomerId,CreatedByUserId,AssignedSellerUserId,Status,DiscountPercent,Subtotal,DiscountAmount,TaxRate,TaxAmount,Total,CustomerMessage)
 VALUES(@CustomerId,@ActorUserId,@AssignedSellerUserId,'DRAFT',@DiscountPercent,@subtotal,@discountAmount,@taxRate,@taxAmount,@total,@CustomerMessage);
 SET @quoteId=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.QuoteItems(QuoteId,ProductId,ProductNameSnapshot,SKUSnapshot,Quantity,UnitPriceAtQuote,ProductSlugSnapshot,DescriptionSnapshot)
 SELECT @quoteId,P.ProductId,P.Name,P.SKU,I.Quantity,P.UnitPrice,P.Slug,P.Description FROM @items I JOIN dbo.Products P ON P.Slug=I.Slug;
 INSERT dbo.QuoteStatusHistory(QuoteId,PreviousStatus,NewStatus,Comment,ChangedByUserId) VALUES(@quoteId,NULL,'DRAFT',N'Cotización creada',@ActorUserId);
 COMMIT;
 SELECT QuoteId AS quoteId,QuoteCode AS quoteCode,Subtotal AS subtotal,DiscountAmount AS discountAmount,TaxAmount AS taxAmount,Total AS total FROM dbo.Quotes WHERE QuoteId=@quoteId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Quote_ChangeStatus @QuoteCode NVARCHAR(30),@ActorUserId INT,@RoleCode VARCHAR(20),@NewStatus VARCHAR(20),@Comment NVARCHAR(1000)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @QuoteId INT,@Current VARCHAR(20),@CustomerId INT,@CustomerUserId INT,@SellerId INT;
 SELECT @QuoteId=Q.QuoteId,@Current=Q.Status,@CustomerId=Q.CustomerId,@CustomerUserId=C.UserId,@SellerId=Q.AssignedSellerUserId
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId WHERE Q.QuoteCode=@QuoteCode;
 IF @QuoteId IS NULL THROW 52201,'Cotización no encontrada.',1;
 IF @NewStatus NOT IN ('PENDING','APPROVED','OBSERVED') THROW 52202,'Estado objetivo inválido.',1;
 IF @RoleCode='CUSTOMER'
 BEGIN IF @CustomerUserId<>@ActorUserId OR @Current<>'PENDING' OR @NewStatus NOT IN ('APPROVED','OBSERVED') THROW 52203,'Transición no permitida para cliente.',1; END
 ELSE IF @RoleCode='SELLER'
 BEGIN IF @SellerId<>@ActorUserId OR @Current<>'DRAFT' OR @NewStatus<>'PENDING' THROW 52204,'Vendedor solo puede enviar sus borradores asignados.',1; END
 ELSE IF @RoleCode='ADMIN'
 BEGIN IF NOT(@Current='DRAFT' AND @NewStatus='PENDING') THROW 52205,'Solo se permite enviar borradores desde esta operación.',1; END
 ELSE THROW 52206,'Rol inválido.',1;
 BEGIN TRANSACTION;
 UPDATE dbo.Quotes SET Status=@NewStatus,ReviewComment=CASE WHEN @NewStatus IN ('APPROVED','OBSERVED') THEN @Comment ELSE ReviewComment END,
  SubmittedAt=CASE WHEN @NewStatus='PENDING' THEN SYSUTCDATETIME() ELSE SubmittedAt END,
  ReviewedAt=CASE WHEN @NewStatus IN ('APPROVED','OBSERVED') THEN SYSUTCDATETIME() ELSE ReviewedAt END,
  UpdatedAt=SYSUTCDATETIME() WHERE QuoteId=@QuoteId;
 INSERT dbo.QuoteStatusHistory(QuoteId,PreviousStatus,NewStatus,Comment,ChangedByUserId) VALUES(@QuoteId,@Current,@NewStatus,@Comment,@ActorUserId);
 COMMIT;
 SELECT QuoteCode AS quoteCode,Status AS status,UpdatedAt AS updatedAt FROM dbo.Quotes WHERE QuoteId=@QuoteId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Admin
AS
BEGIN
 SET NOCOUNT ON;
 SELECT COUNT(*) AS totalQuotes,COALESCE(SUM(CASE WHEN Status='PENDING' THEN 1 ELSE 0 END),0) AS sentQuotes,
  COALESCE(SUM(CASE WHEN Status='APPROVED' THEN 1 ELSE 0 END),0) AS acceptedQuotes,
  COALESCE(SUM(CASE WHEN Status='APPROVED' THEN Total ELSE 0 END),0) AS acceptedRevenue,
  CASE WHEN COUNT(*)=0 THEN 0 ELSE CONVERT(DECIMAL(6,2),100.0*SUM(CASE WHEN Status='APPROVED' THEN 1 ELSE 0 END)/COUNT(*)) END AS conversionRate,
  (SELECT COUNT(*) FROM dbo.Users WHERE RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code='CUSTOMER') AND IsActive=1) AS activeClients,
  (SELECT COUNT(*) FROM dbo.Users WHERE IsActive=1) AS activeUsers FROM dbo.Quotes;
 SELECT TOP(5) Q.QuoteCode AS quoteCode,C.UserId AS customerId,LTRIM(RTRIM(CONCAT(CU.FirstName,N' ',CU.LastName))) AS customerName,C.CompanyName AS customerCompany,
  Q.AssignedSellerUserId AS sellerId,LTRIM(RTRIM(CONCAT(S.FirstName,N' ',S.LastName))) AS sellerName,Q.Status AS status,Q.Total AS total,Q.CreatedAt AS createdAt,
  (SELECT COUNT(*) FROM dbo.QuoteItems I WHERE I.QuoteId=Q.QuoteId) AS itemCount
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId JOIN dbo.Users CU ON CU.UserId=C.UserId LEFT JOIN dbo.Users S ON S.UserId=Q.AssignedSellerUserId ORDER BY Q.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Vendor @UserId INT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT COUNT(*) AS assignedQuotes,COALESCE(SUM(CASE WHEN Status='PENDING' THEN 1 ELSE 0 END),0) AS sentQuotes,
  COALESCE(SUM(CASE WHEN Status='APPROVED' THEN 1 ELSE 0 END),0) AS acceptedQuotes,
  (SELECT COUNT(DISTINCT C.UserId) FROM dbo.Quotes Q2 JOIN dbo.Customers C ON C.CustomerId=Q2.CustomerId WHERE Q2.AssignedSellerUserId=@UserId) AS clientCount
 FROM dbo.Quotes WHERE AssignedSellerUserId=@UserId;
 SELECT TOP(5) Q.QuoteCode AS quoteCode,C.UserId AS customerId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS customerName,C.CompanyName AS customerCompany,
  Q.AssignedSellerUserId AS sellerId,Q.Status AS status,Q.Total AS total,Q.CreatedAt AS createdAt,
  (SELECT COUNT(*) FROM dbo.QuoteItems I WHERE I.QuoteId=Q.QuoteId) AS itemCount
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId JOIN dbo.Users U ON U.UserId=C.UserId
 WHERE Q.AssignedSellerUserId=@UserId ORDER BY Q.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_Client @UserId INT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT COUNT(*) AS totalQuotes,COALESCE(SUM(CASE WHEN Q.Status='PENDING' THEN 1 ELSE 0 END),0) AS sentQuotes,
  COALESCE(SUM(CASE WHEN Q.Status='APPROVED' THEN 1 ELSE 0 END),0) AS acceptedQuotes,
  COALESCE(SUM(CASE WHEN Q.Status='OBSERVED' THEN 1 ELSE 0 END),0) AS rejectedQuotes
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId WHERE C.UserId=@UserId;
 SELECT TOP(5) Q.QuoteCode AS quoteCode,C.UserId AS customerId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS customerName,
  Q.AssignedSellerUserId AS sellerId,LTRIM(RTRIM(CONCAT(S.FirstName,N' ',S.LastName))) AS sellerName,Q.Status AS status,Q.Total AS total,Q.CreatedAt AS createdAt,
  (SELECT COUNT(*) FROM dbo.QuoteItems I WHERE I.QuoteId=Q.QuoteId) AS itemCount
 FROM dbo.Quotes Q JOIN dbo.Customers C ON C.CustomerId=Q.CustomerId JOIN dbo.Users U ON U.UserId=C.UserId LEFT JOIN dbo.Users S ON S.UserId=Q.AssignedSellerUserId
 WHERE C.UserId=@UserId ORDER BY Q.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_Report_AdminOverview
AS
BEGIN
 SET NOCOUNT ON;
 SELECT COALESCE(SUM(CASE WHEN Status='APPROVED' THEN Total ELSE 0 END),0) AS acceptedRevenue,
  CASE WHEN COUNT(*)=0 THEN 0 ELSE CONVERT(DECIMAL(6,2),100.0*SUM(CASE WHEN Status='APPROVED' THEN 1 ELSE 0 END)/COUNT(*)) END AS conversionRate,
  COUNT(*) AS totalQuotes,(SELECT COUNT(*) FROM dbo.Users WHERE RoleId=(SELECT RoleId FROM dbo.Roles WHERE Code='CUSTOMER') AND IsActive=1) AS activeClients
 FROM dbo.Quotes;
 SELECT Status AS status,COUNT(*) AS count FROM dbo.Quotes GROUP BY Status;
 SELECT TOP(1) U.UserId AS sellerId,LTRIM(RTRIM(CONCAT(U.FirstName,N' ',U.LastName))) AS sellerName,U.Email AS sellerEmail,COUNT(*) AS acceptedQuotes
 FROM dbo.Quotes Q JOIN dbo.Users U ON U.UserId=Q.AssignedSellerUserId WHERE Q.Status='APPROVED'
 GROUP BY U.UserId,U.FirstName,U.LastName,U.Email ORDER BY COUNT(*) DESC,U.FirstName;
END;
GO
