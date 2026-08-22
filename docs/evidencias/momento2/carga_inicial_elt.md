# Evidencia E2 — Primera carga ELT: Neon → Snowflake RAW

**Fecha:** 2026-08-21 · **Comando:** `uv run elt_neon_to_snowflake.py` · **Rol:** `TORNEOS_LOADER`

```
Extrayendo sports desde Neon...
  3 filas · columnas: ['ID', 'NAME', 'TYPE']
  OK -> 3 filas en RAW.SPORTS
Extrayendo venues desde Neon...
  4 filas · columnas: ['ID', 'NAME', 'CITY', 'COUNTRY', 'CAPACITY']
  OK -> 4 filas en RAW.VENUES
Extrayendo teams desde Neon...
  6 filas · columnas: ['ID', 'NAME', 'CITY', 'SPORT_ID', 'FOUNDED_YEAR', 'LOGO_URL']
  OK -> 6 filas en RAW.TEAMS
Extrayendo players desde Neon...
  72 filas · columnas: ['ID', 'FIRST_NAME', 'LAST_NAME', 'TEAM_ID', 'POSITION',
                        'JERSEY_NUMBER', 'BIRTH_DATE', 'NATIONALITY']
  OK -> 72 filas en RAW.PLAYERS
Extrayendo tournaments desde Neon...
  2 filas · columnas: ['ID', 'NAME', 'SPORT_ID', 'SEASON', 'START_DATE', 'END_DATE', 'FORMAT']
  OK -> 2 filas en RAW.TOURNAMENTS
Extrayendo referees desde Neon...
  6 filas · columnas: ['ID', 'FIRST_NAME', 'LAST_NAME', 'NATIONALITY', 'CERTIFIED_AT']
  OK -> 6 filas en RAW.REFEREES
Extrayendo matches desde Neon...
  19 filas · columnas: ['ID', 'TOURNAMENT_ID', 'HOME_TEAM_ID', 'AWAY_TEAM_ID',
                        'VENUE_ID', 'SCHEDULED_AT', 'STATUS', 'REFEREE_ID']
  OK -> 19 filas en RAW.MATCHES
Extrayendo match_scores desde Neon...
  17 filas · columnas: ['ID', 'MATCH_ID', 'HOME_SCORE', 'AWAY_SCORE', 'RECORDED_AT']
  OK -> 17 filas en RAW.MATCH_SCORES
Extrayendo match_events desde Neon...
  94 filas · columnas: ['ID', 'MATCH_ID', 'PLAYER_ID', 'EVENT_TYPE', 'MINUTE', 'DETAIL', 'CREATED_AT']
  OK -> 94 filas en RAW.MATCH_EVENTS
```

Las 9 tablas del modelo transaccional quedaron en `TORNEOS_DB.RAW` vía `write_pandas`
(carga masiva por archivos parquet internos — no `INSERT` fila a fila), con el rol de
servicio `TORNEOS_LOADER`, nunca `ACCOUNTADMIN`.
