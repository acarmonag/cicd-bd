# Evidencia E6 — RBAC y Dynamic Data Masking (aplicada en vivo, Enterprise Edition)

**Fecha:** 2026-08-21 · **Scripts:** `snowflake/governance/01_rbac.sql` y `02_masking.sql`

La cuenta del equipo es **Enterprise Edition**, así que `CREATE MASKING POLICY` se
ejecutó y demostró en vivo (no fue necesario el camino alterno de "intento documentado"
que la rúbrica acepta para cuentas Standard).

## 1. RBAC: el alcance del rol es real

Con `ROLE_GERENCIA_COMERCIAL` activo (y `USE SECONDARY ROLES NONE`, ver nota):

```
SELECT * FROM TORNEOS_DB.RAW.PLAYERS LIMIT 1;
-> ERROR: Schema 'TORNEOS_DB.RAW' does not exist or not authorized.

SELECT COUNT(*) FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS;
-> 74 filas   (su dominio sí)
```

> **Nota (hallazgo propio):** los usuarios del trial nacen con
> `DEFAULT_SECONDARY_ROLES = ('ALL')` — la sesión suma los privilegios de *todos* los
> roles del usuario y el SELECT "prohibido" pasa igual. Para demostrar el alcance real
> del rol hay que ejecutar `USE SECONDARY ROLES NONE`. El masking **no** depende de
> esto: las políticas evalúan `CURRENT_ROLE()`, que siempre es el rol primario activo.

## 2. Masking: el MISMO SELECT, tres roles, tres resultados

```sql
SELECT COMPRADOR_NOMBRE, COMPRADOR_EMAIL, COMPRADOR_TELEFONO, PRECIO_USD
FROM TORNEOS_DB.STAGING.STG_VENTAS_TICKETS
WHERE COMPRADOR_TELEFONO IS NOT NULL LIMIT 4;
```

```
--- CURRENT_ROLE() = ROLE_GERENCIA_COMERCIAL (dueña del dato de cliente: ve todo) ---
Isabela Franco     | isabela.franco@hotmail.com     | +57 302 815 2965 | 37.0
Paula Andrea Vélez | paula.andrea.velez@outlook.com | +57 305 393 9356 | 82.0

--- CURRENT_ROLE() = ROLE_ANALISTA_DEPORTIVO (dominio y prefijo: analiza, no identifica) ---
Isabela Franco     | *****@hotmail.com              | +57 302 *** **** | 37.0
Paula Andrea Vélez | *****@outlook.com              | +57 305 *** **** | 82.0

--- CURRENT_ROLE() = ACCOUNTADMIN (administrar la cuenta no es motivo para ver PII) ---
Isabela Franco     | ********                       | *** *** ****     | 37.0
Paula Andrea Vélez | ********                       | *** *** ****     | 82.0
```

## 3. Políticas atadas a columnas

```
SELECT policy_name, ref_column_name
FROM TABLE(TORNEOS_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    ref_entity_name => 'TORNEOS_DB.STAGING.STG_VENTAS_TICKETS', ref_entity_domain => 'TABLE'));

MASK_EMAIL    -> COMPRADOR_EMAIL
MASK_TELEFONO -> COMPRADOR_TELEFONO
```

Una sola copia de la tabla; la política se evalúa al vuelo dentro del plan de cada
query. Cualquier consumidor futuro (BI, notebook) hereda la protección sin configurarla.
