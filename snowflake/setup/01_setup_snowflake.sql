-- ============================================================================
-- 01_setup_snowflake.sql — Arquitectura de la cuenta como código (Momento 2)
--
-- Ejecutar UNA VEZ como ACCOUNTADMIN desde un Worksheet de Snowsight.
-- Todo lo demás (ingesta, tasks, consultas de negocio) corre con roles de
-- mínimo privilegio — nunca ACCOUNTADMIN.
--
-- Crea:
--   * Warehouse WH_TORNEOS (XSMALL, auto-suspend 60s)
--   * Base de datos TORNEOS_DB con tres schemas separados por dominio:
--       RAW      -> datos relacionales extraídos de Neon, sin transformar
--       RAW_JSON -> datos semi-estructurados (ticketing), aterrizan en VARIANT
--       STAGING  -> tablas aplanadas, listas para consumo analítico
--   * Rol de servicio TORNEOS_LOADER para el pipeline Python y las Tasks
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- XSMALL sobra para el volumen del torneo (cientos de filas, no millones).
-- AUTO_SUSPEND agresivo porque Snowflake cobra por segundo de cómputo activo:
-- un warehouse olvidado "prendido" consume el crédito del trial sin hacer nada.
CREATE WAREHOUSE IF NOT EXISTS WH_TORNEOS
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Warehouse del proyecto Torneos Deportivos — Momento 2';

CREATE DATABASE IF NOT EXISTS TORNEOS_DB
    COMMENT = 'Data Warehouse del sistema de torneos deportivos (Momento 1 -> Neon, Momento 2 -> Snowflake)';

-- Un schema por dominio de datos. RAW es intencionalmente "sucio": mismos
-- nombres y tipos que el origen. Si un número se ve raro aguas abajo, la
-- primera pregunta siempre es "¿ya estaba raro en RAW o se rompió después?".
CREATE SCHEMA IF NOT EXISTS TORNEOS_DB.RAW
    COMMENT = 'Landing zone relacional: tablas extraídas de Neon, sin transformar';

CREATE SCHEMA IF NOT EXISTS TORNEOS_DB.RAW_JSON
    COMMENT = 'Landing zone semi-estructurada: exports JSON del proveedor de ticketing, en VARIANT';

CREATE SCHEMA IF NOT EXISTS TORNEOS_DB.STAGING
    COMMENT = 'Datos aplanados y tipados a partir de RAW_JSON — listos para consumo analítico';

-- ----------------------------------------------------------------------------
-- Rol de servicio: TORNEOS_LOADER
-- ----------------------------------------------------------------------------
-- El ELT de Python y las Tasks nunca se conectan como ACCOUNTADMIN. Una
-- credencial filtrada de este rol compromete unas tablas de un schema; una de
-- ACCOUNTADMIN compromete la cuenta completa (usuarios, warehouses, billing).

CREATE ROLE IF NOT EXISTS TORNEOS_LOADER
    COMMENT = 'Rol de servicio: ELT relacional (Python) e ingesta JSON orquestada con Tasks. Sin privilegios de administración.';

GRANT USAGE ON WAREHOUSE WH_TORNEOS TO ROLE TORNEOS_LOADER;
GRANT USAGE ON DATABASE TORNEOS_DB  TO ROLE TORNEOS_LOADER;

-- Dominio relacional: el ELT crea/reescribe tablas en RAW.
GRANT USAGE, CREATE TABLE ON SCHEMA TORNEOS_DB.RAW TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA TORNEOS_DB.RAW TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA TORNEOS_DB.RAW TO ROLE TORNEOS_LOADER;

-- Dominio semi-estructurado: aquí viven el File Format, el External Stage,
-- la tabla VARIANT y las Tasks de ingesta (ver snowflake/json y snowflake/tasks).
GRANT USAGE, CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT, CREATE TASK
    ON SCHEMA TORNEOS_DB.RAW_JSON TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA TORNEOS_DB.RAW_JSON TO ROLE TORNEOS_LOADER;

-- Dominio staging: la Task hija materializa aquí la tabla aplanada.
GRANT USAGE, CREATE TABLE ON SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE TORNEOS_LOADER;

-- EXECUTE TASK es un privilegio de CUENTA, no de objeto: ser dueño de la task
-- no basta para dispararla (verificado en la Sesión 5 del curso).
GRANT EXECUTE TASK ON ACCOUNT TO ROLE TORNEOS_LOADER;

-- Jerarquía recomendada por Snowflake: los roles custom cuelgan de SYSADMIN.
-- Sin esto, las tablas que el loader crea (y posee) quedarían fuera del
-- alcance administrativo — p. ej. atarles una Masking Policy fallaría.
GRANT ROLE TORNEOS_LOADER TO ROLE SYSADMIN;

-- ----------------------------------------------------------------------------
-- Usuarios del equipo
-- ----------------------------------------------------------------------------
-- La cuenta trial nace con un solo usuario (ACARMONAG). Los otros dos
-- integrantes se crean como código. Reemplaza <PASSWORD_TEMPORAL> al ejecutar:
-- la contraseña real nunca se versiona, y MUST_CHANGE_PASSWORD obliga a
-- cambiarla en el primer login.
CREATE USER IF NOT EXISTS MQUIJANOJ
    PASSWORD              = '<PASSWORD_TEMPORAL>'
    MUST_CHANGE_PASSWORD  = TRUE
    DEFAULT_WAREHOUSE     = WH_TORNEOS
    COMMENT               = 'Miguel Quijano — integrante del equipo';

CREATE USER IF NOT EXISTS PRADITA777
    PASSWORD              = '<PASSWORD_TEMPORAL>'
    MUST_CHANGE_PASSWORD  = TRUE
    DEFAULT_WAREHOUSE     = WH_TORNEOS
    COMMENT               = 'Andres Prada — integrante del equipo';

-- Asignación del rol de servicio a los operadores del pipeline.
GRANT ROLE TORNEOS_LOADER TO USER ACARMONAG;
GRANT ROLE TORNEOS_LOADER TO USER MQUIJANOJ;
GRANT ROLE TORNEOS_LOADER TO USER PRADITA777;

-- ----------------------------------------------------------------------------
-- Verificación
-- ----------------------------------------------------------------------------
SHOW WAREHOUSES LIKE 'WH_TORNEOS';
SHOW SCHEMAS IN DATABASE TORNEOS_DB;
SHOW GRANTS TO ROLE TORNEOS_LOADER;
