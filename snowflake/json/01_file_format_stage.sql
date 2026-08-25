-- ============================================================================
-- 01_file_format_stage.sql — Ingesta semi-estructurada, parte 1 (Momento 2)
--
-- Fuente: exports semanales del proveedor de ticketing "TicketAndes"
-- (data/ticketing/*.json en este repositorio, subidos a un bucket S3 de
-- lectura pública). Cada archivo es un ARRAY JSON de órdenes de compra; cada
-- orden trae un array anidado `tickets` — el detalle de boletas.
--
-- Patrón: schema-on-read. El JSON aterriza en una columna VARIANT sin definir
-- su esquema de antemano; la estructura se decide al CONSULTAR, no al cargar.
--
-- Ejecutar con el rol de servicio (los GRANT del setup lo permiten):
--   USE ROLE TORNEOS_LOADER;
-- ============================================================================

USE ROLE TORNEOS_LOADER;
USE WAREHOUSE WH_TORNEOS;
USE SCHEMA TORNEOS_DB.RAW_JSON;

-- STRIP_OUTER_ARRAY = TRUE es obligatorio aquí: cada export es [ {...}, {...} ].
-- Sin esa opción, el archivo completo cargaría como UNA sola fila VARIANT.
CREATE FILE FORMAT IF NOT EXISTS FF_TICKETING_JSON
    TYPE              = JSON
    STRIP_OUTER_ARRAY = TRUE
    COMMENT           = 'Exports de TicketAndes: un array JSON de órdenes por archivo';

-- External Stage: una REFERENCIA al bucket, no una copia de los datos.
-- Bucket de solo lectura pública — suficiente para este momento (el enunciado
-- deja STORAGE INTEGRATION con rol IAM explícitamente fuera de alcance).
CREATE STAGE IF NOT EXISTS STG_TICKETING_S3
    URL         = 's3://s3-tournamet-test-eafit/'
    FILE_FORMAT = FF_TICKETING_JSON
    COMMENT     = 'Bucket S3 con los exports semanales de TicketAndes';

-- Explorar ANTES de cargar: LIST pregunta qué hay; SELECT $1 lee contenido
-- sin moverlo a ninguna tabla. Ninguno consume storage de Snowflake.
LIST @STG_TICKETING_S3;

-- El bucket es compartido y tiene más cosas que nuestros exports (LIST lo
-- muestra). Sin PATTERN, Snowflake intenta parsear TODO como JSON y revienta
-- con el primer PDF que encuentre — el filtro es parte del contrato de ingesta.
SELECT $1
FROM @STG_TICKETING_S3 (
    FILE_FORMAT => FF_TICKETING_JSON,
    PATTERN     => '.*ticketing_export_.*[.]json'
)
LIMIT 3;

-- La tabla de una sola columna: el JSON entero de cada orden en un VARIANT,
-- más metadatos de carga para auditar de qué archivo salió cada fila.
CREATE TABLE IF NOT EXISTS RAW_TICKETING (
    RAW_DATA     VARIANT,
    ARCHIVO      VARCHAR,
    CARGADO_EN   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Primera carga. COPY INTO es idempotente por defecto: recuerda qué archivos
-- ya cargó (metadata del stage) y no los repite — por eso la Task raíz puede
-- ejecutar esta misma sentencia cada día sin duplicar órdenes.
COPY INTO RAW_TICKETING (RAW_DATA, ARCHIVO)
FROM (
    SELECT $1, METADATA$FILENAME
    FROM @STG_TICKETING_S3
)
PATTERN     = '.*ticketing_export_.*[.]json'
FILE_FORMAT = (FORMAT_NAME = FF_TICKETING_JSON);

-- Verificación: filas cargadas y una primera mirada con notación de punto.
SELECT COUNT(*) AS ordenes_cargadas FROM RAW_TICKETING;

SELECT
    RAW_DATA:order_id::STRING          AS orden,
    RAW_DATA:match.external_ref::STRING AS partido,
    RAW_DATA:payment.total_usd::FLOAT  AS total_usd,
    ARRAY_SIZE(RAW_DATA:tickets)       AS num_boletas
FROM RAW_TICKETING
LIMIT 10;
