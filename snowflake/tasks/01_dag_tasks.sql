-- ============================================================================
-- 01_dag_tasks.sql — Orquestación nativa con Snowflake Tasks (Momento 2)
--
-- DAG de dos tareas sobre la fuente semi-estructurada:
--
--   TASK_INGESTA_TICKETING  (raíz, SCHEDULE diario 05:00 Bogotá)
--        │  COPY INTO RAW_TICKETING  — idempotente: solo archivos nuevos
--        ▼  AFTER
--   TASK_APLANAR_TICKETS    (hija, sin reloj propio)
--           INSERT OVERWRITE STG_VENTAS_TICKETS — re-aplana todo el RAW
--
-- La hija NO tiene SCHEDULE: se dispara cuando la raíz termina CON ÉXITO.
-- Eso es una dependencia lógica, no una coincidencia de horarios.
--
-- Dueño: TORNEOS_LOADER (CREATE TASK sobre RAW_JSON y EXECUTE TASK a nivel de
-- cuenta vienen del setup — EXECUTE TASK es privilegio de CUENTA, ser dueño
-- de la task no basta para dispararla).
-- ============================================================================

USE ROLE TORNEOS_LOADER;
USE WAREHOUSE WH_TORNEOS;
USE SCHEMA TORNEOS_DB.RAW_JSON;

-- ----------------------------------------------------------------------------
-- 1. Crear el DAG
-- ----------------------------------------------------------------------------

CREATE TASK IF NOT EXISTS TASK_INGESTA_TICKETING
    WAREHOUSE = WH_TORNEOS
    SCHEDULE  = 'USING CRON 0 5 * * * America/Bogota'
    COMMENT   = 'Raíz del DAG: ingesta diaria de los exports de TicketAndes desde S3'
AS
    COPY INTO RAW_TICKETING (RAW_DATA, ARCHIVO)
    FROM (
        SELECT $1, METADATA$FILENAME
        FROM @STG_TICKETING_S3
    )
    PATTERN     = '.*ticketing_export_.*[.]json'
    FILE_FORMAT = (FORMAT_NAME = FF_TICKETING_JSON);

-- Ojo al orden de las propiedades: COMMENT va ANTES de AFTER — al revés es
-- error de sintaxis (verificado contra Snowflake real en la Sesión 5).
CREATE TASK IF NOT EXISTS TASK_APLANAR_TICKETS
    WAREHOUSE = WH_TORNEOS
    COMMENT   = 'Hija: re-aplana RAW_TICKETING hacia STAGING.STG_VENTAS_TICKETS'
    AFTER TASK_INGESTA_TICKETING
AS
    INSERT OVERWRITE INTO TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
    SELECT
        RAW_DATA:order_id::STRING             AS ORDER_ID,
        RAW_DATA:provider::STRING             AS PROVEEDOR,
        RAW_DATA:purchased_at::TIMESTAMP_NTZ  AS COMPRADA_EN,
        RAW_DATA:channel::STRING              AS CANAL,
        RAW_DATA:match.match_id::NUMBER       AS MATCH_ID,
        RAW_DATA:match.external_ref::STRING   AS PARTIDO_REF,
        RAW_DATA:match.home_team::STRING      AS EQUIPO_LOCAL,
        RAW_DATA:match.away_team::STRING      AS EQUIPO_VISITANTE,
        RAW_DATA:buyer.full_name::STRING      AS COMPRADOR_NOMBRE,
        RAW_DATA:buyer.email::STRING          AS COMPRADOR_EMAIL,
        RAW_DATA:buyer.phone::STRING          AS COMPRADOR_TELEFONO,
        RAW_DATA:buyer.document_id::STRING    AS COMPRADOR_DOCUMENTO,
        RAW_DATA:payment.method::STRING       AS METODO_PAGO,
        RAW_DATA:payment.installments::NUMBER AS CUOTAS,
        boleta.value:ticket_code::STRING      AS TICKET_CODE,
        boleta.value:category::STRING         AS CATEGORIA,
        boleta.value:section::STRING          AS SECCION,
        boleta.value:row::STRING              AS FILA,
        boleta.value:seat::NUMBER             AS ASIENTO,
        boleta.value:price_usd::FLOAT         AS PRECIO_USD,
        ARCHIVO                               AS ARCHIVO_ORIGEN,
        CARGADO_EN
    FROM RAW_TICKETING,
         LATERAL FLATTEN(input => RAW_DATA:tickets) boleta;

-- Las tasks nacen SUSPENDIDAS. Verificar el estado:
SHOW TASKS IN SCHEMA TORNEOS_DB.RAW_JSON;

-- ----------------------------------------------------------------------------
-- 2. Activar el DAG completo
-- ----------------------------------------------------------------------------
-- Resuelve raíz e hijas de un solo golpe, en el orden correcto.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('TORNEOS_DB.RAW_JSON.TASK_INGESTA_TICKETING');

-- ----------------------------------------------------------------------------
-- 3. Disparo manual (la demo no espera a las 05:00)
-- ----------------------------------------------------------------------------
EXECUTE TASK TASK_INGESTA_TICKETING;

-- ----------------------------------------------------------------------------
-- 4. Evidencia: TASK_HISTORY — primera parada para depurar, siempre
-- ----------------------------------------------------------------------------
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(TORNEOS_DB.INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_INGESTA_TICKETING', 'TASK_APLANAR_TICKETS')
ORDER BY scheduled_time DESC
LIMIT 10;

-- Confirmar que la hija dejó la tabla de staging consistente:
SELECT COUNT(*) AS boletas FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS;

-- ----------------------------------------------------------------------------
-- 5. Apagar el DAG — EL ORDEN NO ES LIBRE
-- ----------------------------------------------------------------------------
-- Suspender la hija (o alterar cualquier task) con la raíz activa falla con
-- el error 091421: hay que suspender la RAÍZ primero, siempre.
ALTER TASK TASK_INGESTA_TICKETING SUSPEND;
ALTER TASK TASK_APLANAR_TICKETS   SUSPEND;

SHOW TASKS IN SCHEMA TORNEOS_DB.RAW_JSON;
