/*
  Ejecutar dentro de db-cotizaciones con una cuenta administrativa después de crear dbo procedures.
  Requiere que el database user [app_cotizaciones] ya exista y esté ligado al login SQL de aplicación.
  Concede ejecución de procedimientos en dbo; no concede permisos DDL ni acceso de lectura directo a tablas.
*/
USE [db-cotizaciones];
GO
IF DATABASE_PRINCIPAL_ID(N'app_cotizaciones') IS NULL
    THROW 54001, 'Crea primero el database user app_cotizaciones vinculado a su login SQL.', 1;
GRANT EXECUTE ON SCHEMA::dbo TO [app_cotizaciones];
GO
