# Evidencia E3 — Schema drift: caso provocado y su corrección

**Fecha:** 2026-08-21 · **Tabla afectada:** `matches` · **Columna:** `attendance`

## 1. El incidente (provocado a propósito)

Simulamos lo que haría el equipo de backend sin avisar al equipo de datos: agregar una
columna en la fuente relacional (Neon, branch `dev`) por fuera del pipeline.

```sql
-- Ejecutado directamente contra Neon dev
ALTER TABLE matches ADD COLUMN attendance INTEGER;
UPDATE matches SET attendance = 12000 + (id * 937) % 28000 WHERE status = 'finished';
```

## 2. El ELT detecta el drift ANTES de cargar

```
$ uv run elt_neon_to_snowflake.py --tabla matches

Extrayendo matches desde Neon...
  19 filas · columnas: ['ID', 'TOURNAMENT_ID', 'HOME_TEAM_ID', 'AWAY_TEAM_ID',
                        'VENUE_ID', 'SCHEDULED_AT', 'STATUS', 'REFEREE_ID', 'ATTENDANCE']

ERROR:
Schema drift detectado en MATCHES: la fuente en Neon trae columna(s) nueva(s)
que Snowflake no tiene todavía: ['ATTENDANCE'].

Aplica esto en un Worksheet de Snowsight y vuelve a correr el script:

ALTER TABLE MATCHES ADD COLUMN "ATTENDANCE" FLOAT;
```

Puntos clave del comportamiento:

- El script **no tocó Snowflake**: la comparación de columnas (DataFrame vs.
  `information_schema.columns` del destino) ocurre antes de `write_pandas`.
- El mensaje es **accionable**: dice tabla, columna, y trae el DDL de roll-forward ya
  redactado — no el `invalid identifier` críptico que daría Snowflake tres capas más
  abajo.
- El tipo propuesto es `FLOAT` y no `NUMBER` porque los partidos no finalizados tienen
  `attendance` en `NULL`, y pandas representa enteros con nulos como `float64`. Es el
  mapeo aproximado deliberado de la capa RAW — el tipado fino es de capas posteriores.
- El DDL **se muestra, no se ejecuta solo**: alterar el schema del warehouse sin que
  nadie lo revise es su propio riesgo.

## 3. El roll-forward y la corrección

Se aplicó el DDL propuesto en Snowflake (rol `TORNEOS_LOADER`, dueño de la tabla):

```sql
ALTER TABLE MATCHES ADD COLUMN "ATTENDANCE" FLOAT;
```

Y se volvió a correr el ELT **sin tocar una línea de código**:

```
$ uv run elt_neon_to_snowflake.py --tabla matches

Extrayendo matches desde Neon...
  19 filas · columnas: ['ID', 'TOURNAMENT_ID', 'HOME_TEAM_ID', 'AWAY_TEAM_ID',
                        'VENUE_ID', 'SCHEDULED_AT', 'STATUS', 'REFEREE_ID', 'ATTENDANCE']
  OK -> 19 filas en RAW.MATCHES
```

La extracción con `SELECT *` recogió la columna nueva sola; la detección de drift fue
la que decidió frenar la carga hasta que el destino evolucionara. Mismo criterio que
Flyway en el Momento 1: **detectar antes de fallar**.
