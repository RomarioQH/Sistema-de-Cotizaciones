/* Solo lectura: confirma base seleccionada, tablas, columnas y procedimientos existentes. */
SET NOCOUNT ON;
SELECT DB_NAME() AS BaseDeDatosActual;
SELECT s.name AS Esquema, t.name AS Tabla
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
ORDER BY s.name,t.name;
SELECT TABLE_SCHEMA,TABLE_NAME,COLUMN_NAME,DATA_TYPE,IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Roles','Users','Customers','Products','Quotes','QuoteItems','QuoteStatusHistory')
ORDER BY TABLE_NAME,ORDINAL_POSITION;
SELECT SCHEMA_NAME(schema_id) AS Esquema,name AS Procedimiento
FROM sys.procedures ORDER BY SCHEMA_NAME(schema_id),name;
