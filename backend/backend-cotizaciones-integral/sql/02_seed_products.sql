/* Demo catalog matching the Angular demo-data service. Review before using live business prices.
   Deactivates only four sample products inserted by the earlier starter seed, not arbitrary products. */
SET NOCOUNT ON;
GO
UPDATE dbo.Products SET IsActive=0,UpdatedAt=SYSUTCDATETIME()
WHERE SKU IN (N'SW-LIC-001',N'DEV-HR-001',N'SUP-HR-001',N'ROUTER-001');
GO
MERGE dbo.Products AS target
USING (VALUES
 ('web','SKU-WEB',N'Desarrollo Web Profesional',N'Desarrollo Web',N'Sitio web responsivo con diseño moderno y optimizado para SEO',CAST(1500.00 AS DECIMAL(12,2)),'S'),
 ('mobile','SKU-MOBILE',N'Aplicación Móvil iOS/Android',N'Desarrollo Móvil',N'App nativa con interfaz intuitiva y funcionalidades avanzadas',CAST(3500.00 AS DECIMAL(12,2)),'S'),
 ('crm','SKU-CRM',N'Sistema de Gestión (CRM)',N'Software Empresarial',N'Plataforma completa para gestión de clientes y ventas',CAST(2800.00 AS DECIMAL(12,2)),'S'),
 ('ecommerce','SKU-ECOMMERCE',N'E-commerce Completo',N'Desarrollo Web',N'Tienda online con pasarela de pagos y panel administrativo',CAST(2200.00 AS DECIMAL(12,2)),'S')
) AS src(Slug,SKU,Name,Category,Description,UnitPrice,ProductType)
ON target.Slug=src.Slug
WHEN MATCHED THEN UPDATE SET SKU=src.SKU,Name=src.Name,Category=src.Category,Description=src.Description,UnitPrice=src.UnitPrice,ProductType=src.ProductType,IsActive=1,UpdatedAt=SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT(Slug,SKU,Name,Category,Description,UnitPrice,ProductType,IsStockManaged,StockQuantity,IsActive)
VALUES(src.Slug,src.SKU,src.Name,src.Category,src.Description,src.UnitPrice,src.ProductType,0,NULL,1);
GO
SELECT ProductId,Slug,SKU,Name,Category,UnitPrice,Currency,IsActive FROM dbo.Products ORDER BY Name;
GO
