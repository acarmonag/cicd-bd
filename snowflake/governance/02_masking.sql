-- ============================================================================
-- 02_masking.sql — Dynamic Data Masking sobre la PII de compradores (Momento 2)
--
-- Requiere Snowflake ENTERPRISE Edition (en Standard, CREATE MASKING POLICY
-- falla con "Unsupported feature" — si ese fuera el caso, este script queda
-- como la política escrita + el error como evidencia del intento, que la
-- rúbrica acepta).
--
-- La PII vive en STAGING.STG_VENTAS_TICKETS: email y teléfono del comprador,
-- que llegaron dentro del JSON de TicketAndes. La política se evalúa AL VUELO
-- dentro de cada query — no existe una segunda copia enmascarada de la tabla.
--
-- Quién ve qué (mismo SELECT, tres resultados):
--   ROLE_GERENCIA_COMERCIAL   dueña de la relación con el cliente -> ve todo
--   ROLE_ANALISTA_DEPORTIVO   analiza demanda, no identidades     -> parcial
--   cualquier otro rol        incluido ACCOUNTADMIN               -> oculto
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_TORNEOS;
USE SCHEMA TORNEOS_DB.STAGING;

-- ----------------------------------------------------------------------------
-- 1. Políticas
-- ----------------------------------------------------------------------------

-- Email: el analista conserva el dominio (útil para analizar canales de
-- compra) pero pierde la identidad; el resto no ve nada.
CREATE MASKING POLICY IF NOT EXISTS MASK_EMAIL
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() = 'ROLE_GERENCIA_COMERCIAL' THEN val
        WHEN CURRENT_ROLE() = 'ROLE_ANALISTA_DEPORTIVO'
            THEN '*****@' || SPLIT_PART(val, '@', 2)
        ELSE '********'
    END;

-- Teléfono: el analista conserva el prefijo de operador (+57 3xx); el resto
-- no ve nada. NULL entra y sale NULL — la política no inventa datos.
CREATE MASKING POLICY IF NOT EXISTS MASK_TELEFONO
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN val IS NULL THEN NULL
        WHEN CURRENT_ROLE() = 'ROLE_GERENCIA_COMERCIAL' THEN val
        WHEN CURRENT_ROLE() = 'ROLE_ANALISTA_DEPORTIVO'
            THEN LEFT(val, 7) || ' *** ****'
        ELSE '*** *** ****'
    END;

-- ----------------------------------------------------------------------------
-- 2. Atar las políticas a las columnas — una sola vez; toda consulta futura
--    (dashboard, notebook, lo que sea) hereda la protección automáticamente.
-- ----------------------------------------------------------------------------
ALTER TABLE STG_VENTAS_TICKETS
    MODIFY COLUMN COMPRADOR_EMAIL SET MASKING POLICY MASK_EMAIL;

ALTER TABLE STG_VENTAS_TICKETS
    MODIFY COLUMN COMPRADOR_TELEFONO SET MASKING POLICY MASK_TELEFONO;

-- ----------------------------------------------------------------------------
-- 3. Demo: el MISMO SELECT, tres resultados distintos
-- ----------------------------------------------------------------------------

-- (Se filtra a teléfonos no nulos para que el contraste entre roles se vea —
--  recordar que ~1/3 de los compradores no dio teléfono y ahí NULL es NULL.)

-- 3a. Gerencia comercial: PII completa (es la dueña del dato de cliente).
USE ROLE ROLE_GERENCIA_COMERCIAL;
SELECT COMPRADOR_NOMBRE, COMPRADOR_EMAIL, COMPRADOR_TELEFONO, PRECIO_USD
FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
WHERE COMPRADOR_TELEFONO IS NOT NULL
LIMIT 5;

-- 3b. Analista deportivo: dominio del email y prefijo del teléfono.
USE ROLE ROLE_ANALISTA_DEPORTIVO;
SELECT COMPRADOR_NOMBRE, COMPRADOR_EMAIL, COMPRADOR_TELEFONO, PRECIO_USD
FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
WHERE COMPRADOR_TELEFONO IS NOT NULL
LIMIT 5;

-- 3c. ACCOUNTADMIN: todo oculto — poder administrar la cuenta no es motivo
--     para ver la PII de los compradores.
USE ROLE ACCOUNTADMIN;
SELECT COMPRADOR_NOMBRE, COMPRADOR_EMAIL, COMPRADOR_TELEFONO, PRECIO_USD
FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
WHERE COMPRADOR_TELEFONO IS NOT NULL
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 4. Verificación de qué política cubre qué columna
-- ----------------------------------------------------------------------------
SELECT policy_name, ref_column_name
FROM TABLE(TORNEOS_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    ref_entity_name   => 'TORNEOS_DB.STAGING.STG_VENTAS_TICKETS',
    ref_entity_domain => 'TABLE'
));
