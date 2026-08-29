-- ============================================================================
-- 00_dbt_setup.sql — Permisos Snowflake para el proyecto dbt (Momento 3)
--
-- Ejecutar UNA VEZ como SYSADMIN desde Snowsight, DESPUÉS de haber corrido
-- snowflake/setup/01_setup_snowflake.sql del Momento 2.
--
-- Crea el schema CORE (capa Gold del Medallón) y otorga a TORNEOS_LOADER
-- los privilegios necesarios para que dbt build funcione sin ACCOUNTADMIN.
-- ============================================================================

USE ROLE SYSADMIN;
USE DATABASE TORNEOS_DB;
USE WAREHOUSE WH_TORNEOS;

-- Schema Gold: aquí dbt materializa los modelos de core/ como TABLE.
-- STAGING (Silver) ya existe del Momento 2 — dbt reutiliza ese schema.
CREATE SCHEMA IF NOT EXISTS TORNEOS_DB.CORE
    COMMENT = 'Capa Gold del Medallón: modelos analíticos listos para consumo, construidos por dbt.';

-- dbt necesita CREATE SCHEMA en la base de datos para poder crear schemas
-- desde el runner de CI (por si el schema aún no existe al momento del build).
GRANT CREATE SCHEMA ON DATABASE TORNEOS_DB TO ROLE TORNEOS_LOADER;

-- Permisos sobre STAGING para las vistas Silver de dbt.
GRANT USAGE ON SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;
GRANT CREATE VIEW ON SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;
GRANT SELECT ON ALL TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;

-- Permisos sobre CORE para las tablas Gold de dbt.
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA TORNEOS_DB.CORE TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA TORNEOS_DB.CORE TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA TORNEOS_DB.CORE TO ROLE TORNEOS_LOADER;

-- Verificación
SHOW SCHEMAS IN DATABASE TORNEOS_DB;
SHOW GRANTS TO ROLE TORNEOS_LOADER;
