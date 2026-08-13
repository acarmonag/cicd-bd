-- Limpieza de esquema heredado. Segura en base de datos nueva (IF EXISTS).
-- flyway_schema_history NO se incluye — Flyway lo gestiona internamente.
DROP VIEW  IF EXISTS vw_sales_summary;
DROP TABLE IF EXISTS web_events    CASCADE;
DROP TABLE IF EXISTS orders        CASCADE;
DROP TABLE IF EXISTS accounts      CASCADE;
DROP TABLE IF EXISTS sales_reps    CASCADE;
DROP TABLE IF EXISTS regions       CASCADE;
DROP TABLE IF EXISTS products      CASCADE;
