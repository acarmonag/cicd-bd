-- ============================================================================
-- 01_rbac.sql — Roles de negocio (Momento 2)
--
-- Ejecutar como ACCOUNTADMIN (crear roles y otorgar es administración de la
-- cuenta; el día a día NUNCA corre con este rol).
--
-- Dos roles de negocio con necesidades de acceso DISTINTAS — el punto de
-- partida es "todo cerrado", cada GRANT es una puerta que se abre a propósito:
--
--   ROLE_ANALISTA_DEPORTIVO   Analiza rendimiento: partidos, marcadores,
--                             plantillas (RAW relacional) y demanda de boletas
--                             (STAGING). NO necesita la identidad de los
--                             compradores -> verá la PII enmascarada.
--
--   ROLE_GERENCIA_COMERCIAL   Gestiona la relación con los compradores
--                             (recaudo, CRM): solo STAGING. Es la dueña del
--                             dato de cliente -> ve la PII completa. No tiene
--                             nada que hacer en las tablas deportivas crudas.
--
-- (El tercer rol del sistema es TORNEOS_LOADER, de servicio — snowflake/setup.)
-- ============================================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS ROLE_ANALISTA_DEPORTIVO
    COMMENT = 'Análisis deportivo: lee RAW relacional y STAGING; PII enmascarada';

CREATE ROLE IF NOT EXISTS ROLE_GERENCIA_COMERCIAL
    COMMENT = 'Gestión comercial/CRM: lee solo STAGING; ve la PII de compradores';

-- Ambos necesitan cómputo y llegar a la base de datos.
GRANT USAGE ON WAREHOUSE WH_TORNEOS TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT USAGE ON WAREHOUSE WH_TORNEOS TO ROLE ROLE_GERENCIA_COMERCIAL;
GRANT USAGE ON DATABASE TORNEOS_DB  TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT USAGE ON DATABASE TORNEOS_DB  TO ROLE ROLE_GERENCIA_COMERCIAL;

-- --- Analista deportivo: RAW relacional + STAGING, solo lectura -------------
GRANT USAGE ON SCHEMA TORNEOS_DB.RAW     TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT USAGE ON SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT SELECT ON ALL TABLES    IN SCHEMA TORNEOS_DB.RAW     TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT SELECT ON FUTURE TABLES IN SCHEMA TORNEOS_DB.RAW     TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT SELECT ON ALL TABLES    IN SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_ANALISTA_DEPORTIVO;
GRANT SELECT ON FUTURE TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_ANALISTA_DEPORTIVO;
-- Deliberadamente SIN acceso a RAW_JSON: el VARIANT crudo contiene la PII
-- sin enmascarar — abrirlo dejaría la Masking Policy pintada en la pared.

-- --- Gerencia comercial: SOLO staging, solo lectura --------------------------
GRANT USAGE ON SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_GERENCIA_COMERCIAL;
GRANT SELECT ON ALL TABLES    IN SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_GERENCIA_COMERCIAL;
GRANT SELECT ON FUTURE TABLES IN SCHEMA TORNEOS_DB.STAGING TO ROLE ROLE_GERENCIA_COMERCIAL;
-- Sin RAW (tablas deportivas) y sin RAW_JSON (VARIANT crudo).

-- --- Asignación a los integrantes del equipo --------------------------------
GRANT ROLE ROLE_ANALISTA_DEPORTIVO TO USER ACARMONAG;
GRANT ROLE ROLE_ANALISTA_DEPORTIVO TO USER MQUIJANOJ;
GRANT ROLE ROLE_ANALISTA_DEPORTIVO TO USER PRADITA777;
GRANT ROLE ROLE_GERENCIA_COMERCIAL TO USER ACARMONAG;
GRANT ROLE ROLE_GERENCIA_COMERCIAL TO USER MQUIJANOJ;
GRANT ROLE ROLE_GERENCIA_COMERCIAL TO USER PRADITA777;

-- --- Verificación ------------------------------------------------------------
SHOW GRANTS TO ROLE ROLE_ANALISTA_DEPORTIVO;
SHOW GRANTS TO ROLE ROLE_GERENCIA_COMERCIAL;

-- La diferencia de alcance, demostrada: la gerencia comercial NO puede tocar
-- las tablas deportivas crudas (esto debe FALLAR con "not authorized").
--
-- OJO: los usuarios del trial nacen con DEFAULT_SECONDARY_ROLES = ('ALL') —
-- la sesión suma los privilegios de TODOS los roles del usuario, y el SELECT
-- "prohibido" pasa igual. Para demostrar el alcance real del rol hay que
-- desactivar los roles secundarios en la sesión (el masking no necesita esto:
-- las políticas evalúan CURRENT_ROLE(), que siempre es el rol primario).
-- USE ROLE ROLE_GERENCIA_COMERCIAL;
-- USE SECONDARY ROLES NONE;
-- SELECT * FROM TORNEOS_DB.RAW.PLAYERS LIMIT 1;   -- -> "not authorized"
