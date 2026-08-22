# Evidencia E4 — Ingesta semi-estructurada: External Stage + VARIANT + FLATTEN

**Fecha:** 2026-08-21 · **Scripts:** `snowflake/json/01_file_format_stage.sql` y `02_flatten_staging.sql` · **Rol:** `TORNEOS_LOADER`

## 1. El bucket real tenía más cosas que nuestros exports

El primer `COPY INTO` (sin filtro) reventó con un archivo ajeno que vivía en el mismo
bucket compartido:

```
ProgrammingError: 100069 (22P02): Error parsing JSON: invalid character
outside of a string: '%'
  File 'test/Antonio_Carmona_CV_1.pdf', line 1, character 1
```

Corrección: `PATTERN = '.*ticketing_export_.*[.]json'` tanto en la exploración como en
el `COPY INTO` (y en la Task raíz). El filtro es parte del contrato de ingesta — un
bucket real nunca contiene solo lo tuyo.

## 2. Carga a VARIANT (schema-on-read)

`COPY INTO RAW_TICKETING` cargó los 3 exports → **28 órdenes** (8 + 10 + 10), cada una
como un `VARIANT` con su archivo de origen:

```
ORDEN             | PARTIDO     | TOTAL_USD | NUM_BOLETAS
TKA-20260807-0001 | CM2026-Q2   | 37.0      | 1
TKA-20260807-0002 | LMF2026-M14 | 246.0     | 3
TKA-20260807-0005 | CM2026-SF1  | 328.0     | 4
...
```

Re-ejecutar el mismo `COPY INTO` carga **0 filas**: es idempotente (metadata del stage
recuerda qué archivos ya procesó) — por eso la Task raíz puede correr a diario.

## 3. LATERAL FLATTEN → STAGING.STG_VENTAS_TICKETS

28 órdenes se convirtieron en **74 boletas** (una fila por elemento del array anidado
`tickets`). Verificación por partido, con el manejo de claves ausentes a la vista:

```
PARTIDO_REF | BOLETAS | RECAUDO_USD | BOLETAS_SIN_SECCION | ORDENES
LMF2026-M14 |      19 |      1276.0 |                  14 |       7
LMF2026-M15 |      22 |      1008.0 |                   6 |       7
CM2026-SF1  |      14 |       603.0 |                   4 |       5
CM2026-Q2   |      12 |       458.0 |                   2 |       6
CM2026-Q3   |       4 |       148.0 |                   0 |       2
CM2026-Q1   |       3 |        54.0 |                   0 |       1
```

Claves ausentes — la consulta no falla, la columna sale `NULL`:

- `tickets[].section`: 26 de 74 boletas sin sección (las de palco no traen la clave).
- `buyer.phone`: 40 de 74 filas con teléfono (28 órdenes, ~1/3 de compradores no lo dio).
- `payment.installments`: 19 de 74 (solo compras con tarjeta de crédito).
