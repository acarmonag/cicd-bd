-- ============================================================================
-- 02_flatten_staging.sql — Ingesta semi-estructurada, parte 2 (Momento 2)
--
-- Del VARIANT crudo a una tabla aplanada y tipada: notación de punto para los
-- campos de la orden, LATERAL FLATTEN para desenrollar el array anidado
-- `tickets` (una fila de salida por boleta, no por orden).
--
-- Manejo de claves ausentes — verificado sobre los datos reales:
--   * buyer.phone no viene en ~1/3 de las órdenes  -> sale NULL, no falla.
--   * tickets[i].section no viene en boletas palco -> sale NULL, no falla.
--   * payment.installments solo existe en tarjeta  -> sale NULL, no falla.
-- ============================================================================

USE ROLE TORNEOS_LOADER;
USE WAREHOUSE WH_TORNEOS;
USE SCHEMA TORNEOS_DB.RAW_JSON;

-- ----------------------------------------------------------------------------
-- Exploración: notación de punto sobre los campos planos de la orden
-- ----------------------------------------------------------------------------
-- Sin ::TIPO todo sale VARIANT (ni se suma ni se compara). El cast es parte
-- del contrato de salida, no un adorno.
SELECT
    RAW_DATA:order_id::STRING            AS order_id,
    RAW_DATA:purchased_at::TIMESTAMP_NTZ AS purchased_at,
    RAW_DATA:channel::STRING             AS canal,
    RAW_DATA:buyer.full_name::STRING     AS comprador,
    RAW_DATA:buyer.phone::STRING         AS telefono,      -- NULL si no vino
    RAW_DATA:payment.total_usd::FLOAT    AS total_usd
FROM RAW_TICKETING
LIMIT 10;

-- ----------------------------------------------------------------------------
-- LATERAL FLATTEN: una fila por BOLETA
-- ----------------------------------------------------------------------------
-- FLATTEN multiplica la fila de la orden una vez por cada elemento del array:
-- una orden con 4 boletas produce 4 filas. LATERAL es lo que le permite a
-- FLATTEN ver la columna RAW_DATA de la fila que se está procesando.
SELECT
    RAW_DATA:order_id::STRING       AS order_id,
    boleta.value:ticket_code::STRING AS ticket_code,
    boleta.value:category::STRING    AS categoria,
    boleta.value:section::STRING     AS seccion,        -- NULL en palcos
    boleta.value:price_usd::FLOAT    AS precio_usd
FROM RAW_TICKETING,
     LATERAL FLATTEN(input => RAW_DATA:tickets) boleta
LIMIT 15;

-- ----------------------------------------------------------------------------
-- Materialización: STAGING.STG_VENTAS_TICKETS
-- ----------------------------------------------------------------------------
-- La misma consulta, materializada. La Task hija (snowflake/tasks) refresca
-- esta tabla con INSERT OVERWRITE después de cada ingesta — una sentencia,
-- conserva los GRANT, y deja la tabla consistente con RAW_TICKETING.
CREATE TABLE IF NOT EXISTS TORNEOS_DB.STAGING.STG_VENTAS_TICKETS AS
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

-- Verificación: boletas por partido y NULL donde el JSON no traía la clave.
SELECT PARTIDO_REF,
       COUNT(*)                                   AS boletas,
       SUM(PRECIO_USD)                            AS recaudo_usd,
       COUNT(*) - COUNT(SECCION)                  AS boletas_sin_seccion,
       COUNT(DISTINCT ORDER_ID)                   AS ordenes
FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
GROUP BY PARTIDO_REF
ORDER BY recaudo_usd DESC;
