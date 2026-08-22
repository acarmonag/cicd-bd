# Momento 2 — Documento de decisiones

**Proyecto:** Sistema de Torneos Deportivos · **Equipo:** Miguel Quijano, Andres Prada, Antonio Carmona
**Stack:** Snowflake (TORNEOS_DB) · Neon PostgreSQL (Momento 1) · Python con `uv` · S3

---

## 1. Qué fuente semi-estructurada elegimos, y por qué

Elegimos los **exports semanales del proveedor de ticketing "TicketAndes"**: archivos
JSON con las órdenes de compra de boletas para los partidos del torneo.

**Por qué esta fuente y no otra:**

- **No existe en el modelo relacional del Momento 1.** Nuestro esquema transaccional
  cubre lo deportivo (equipos, jugadores, partidos, marcadores, eventos); la venta de
  boletas es un proceso que ocurre *fuera* de nuestro sistema, en la plataforma de un
  tercero. Es exactamente el caso que el momento pide: una segunda fuente, más
  desordenada, que también importa al negocio.
- **Su forma es genuinamente semi-estructurada.** Cada orden trae un **array anidado
  `tickets`** (una orden compra 1–4 boletas), que es lo que justifica `LATERAL FLATTEN`:
  la pregunta de negocio ("¿cuánto recaudó cada partido, por sección?") se responde por
  *boleta*, no por orden. Además hay **claves que no siempre vienen** — `buyer.phone`
  (~1 de cada 3 compradores no lo da), `tickets[].section` (los palcos no tienen
  sección) y `payment.installments` (solo compras con tarjeta) — el caso real de manejo
  de claves ausentes: la consulta no falla, la columna sale `NULL`.
- **Un proveedor externo no negocia su esquema contigo.** Definir columnas fijas de
  antemano (schema-on-write) nos dejaría rotos ante el primer cambio del proveedor. Por
  eso el JSON aterriza en una columna `VARIANT` (schema-on-read) y la estructura se
  decide al consultar, en `STAGING`.
- El proveedor sí conoce nuestro `match_id` (el organizador registra cada partido en la
  plataforma al abrir la venta), lo que permite cruzar el recaudo con las tablas
  relacionales de `RAW` sin inventar llaves.

Los datos son sintéticos (el enunciado lo permite) pero la *forma* replica un export
real: un array JSON de órdenes por archivo, un export por semana, en un bucket S3 de
solo lectura (`STORAGE INTEGRATION` con IAM quedó fuera de alcance por enunciado).

## 2. Estrategia de roles

Tres roles, tres necesidades, y el punto de partida siempre es "todo cerrado":

| Rol | Para qué existe | Qué ve |
|---|---|---|
| `TORNEOS_LOADER` (servicio) | Ejecuta el ELT de Python y es dueño de las Tasks. | Escribe en `RAW`, `RAW_JSON` y `STAGING`. Sin ningún privilegio de administración de cuenta — nunca `ACCOUNTADMIN`. |
| `ROLE_ANALISTA_DEPORTIVO` (negocio) | Análisis de rendimiento y demanda: partidos, marcadores, boletas por sección. | Lectura de `RAW` y `STAGING`. **PII enmascarada parcialmente**: conserva el dominio del email y el prefijo del teléfono (le sirven para analizar canales), pierde la identidad. |
| `ROLE_GERENCIA_COMERCIAL` (negocio) | Relación con los compradores: recaudo, CRM, recompra. | **Solo `STAGING`** — nada que hacer en las tablas deportivas crudas. Es la dueña del dato de cliente: **ve la PII completa**. |

Decisiones deliberadas detrás de la tabla:

- **Nadie de negocio entra a `RAW_JSON`.** El `VARIANT` crudo contiene la PII sin
  enmascarar; dar `SELECT` ahí dejaría la Masking Policy pintada en la pared. La
  protección solo es real si el único camino al dato pasa por las columnas protegidas.
- **La visibilidad la decide la necesidad, no la jerarquía.** `ACCOUNTADMIN` cae en el
  `ELSE` de las políticas y ve `********`: administrar la cuenta no es motivo para ver
  teléfonos de compradores.
- **Masking sobre `COMPRADOR_EMAIL` y `COMPRADOR_TELEFONO`** en
  `STAGING.STG_VENTAS_TICKETS`, con **Dynamic Data Masking** (Enterprise Edition): una
  sola copia de la tabla, la política se evalúa al vuelo en cada query, y cualquier
  consumidor futuro (BI, notebooks) hereda la protección sin configurar nada.

## 3. Otras decisiones que nos preguntarán

- **Schemas separados por dominio** (`RAW` relacional, `RAW_JSON` semi-estructurado,
  `STAGING` aplanado): auditabilidad — si un número se ve raro, la primera pregunta es
  "¿ya estaba raro en RAW?"— y permisos por dominio sin excepciones por tabla.
- **Drift antes de cargar, con el DDL ya redactado.** El ELT compara columnas del
  DataFrame contra `information_schema.columns` del destino y falla con el
  `ALTER TABLE` exacto para el roll-forward — no con el `invalid identifier` críptico
  tres capas más abajo. Caso provocado y corregido: `matches.attendance`
  (ver `docs/evidencias/momento2/`).
- **El DAG refresca con `INSERT OVERWRITE`**, no `CREATE OR REPLACE`: una sola
  sentencia (una Task = una sentencia), conserva los `GRANT` y las masking policies
  atadas a la tabla, y deja `STAGING` consistente con `RAW_JSON` en cada corrida.
- **`COPY INTO` es idempotente** (metadata del stage): la Task raíz puede correr todos
  los días sin duplicar órdenes; solo carga archivos nuevos del bucket.
