# Evidencia E5 — DAG de Tasks: ejecución y administración

**Fecha:** 2026-08-21 · **Script:** `snowflake/tasks/01_dag_tasks.sql` · **Rol:** `TORNEOS_LOADER` (dueño de las tasks)

## 1. El DAG activo

```
SHOW TASKS IN SCHEMA TORNEOS_DB.RAW_JSON;

  TASK_APLANAR_TICKETS     state=started   schedule=None                            (hija, AFTER)
  TASK_INGESTA_TICKETING   state=started   schedule=USING CRON 0 5 * * * America/Bogota  (raíz)
```

Activado con un solo comando — resuelve raíz e hijas en el orden correcto:

```sql
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('TORNEOS_DB.RAW_JSON.TASK_INGESTA_TICKETING');
```

## 2. Disparo manual y TASK_HISTORY (ejecución exitosa encadenada)

```sql
EXECUTE TASK TASK_INGESTA_TICKETING;

SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(TORNEOS_DB.INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name IN ('TASK_INGESTA_TICKETING','TASK_APLANAR_TICKETS')
ORDER BY scheduled_time DESC;
```

```
NAME                    STATE      INICIO (Bogotá)          FIN (Bogotá)             ERROR
TASK_INGESTA_TICKETING  SCHEDULED  2026-08-22 05:00:00      —                        None   <- próxima corrida programada
TASK_APLANAR_TICKETS    SUCCEEDED  2026-08-21 21:35:46.767  2026-08-21 21:35:48.691  None
TASK_INGESTA_TICKETING  SUCCEEDED  2026-08-21 21:35:45.219  2026-08-21 21:35:46.767  None
```

La hija arrancó cuando la raíz terminó **con éxito** (21:35:46.767 — mismo instante):
dependencia lógica, no coincidencia de horarios. Tras la corrida,
`STAGING.STG_VENTAS_TICKETS` quedó con **74 boletas**, consistente con `RAW_TICKETING`.

## 3. Apagado: el orden NO es libre

Intentar suspender la hija con la raíz activa falla (error real, no teórico):

```
ALTER TASK TASK_APLANAR_TICKETS SUSPEND;
-> 091421 (22000): Unable to update graph with root task
   TORNEOS_DB.RAW_JSON.TASK_INGESTA_TICKETING since that root task is not suspended.
```

Orden correcto — la raíz primero, siempre:

```
ALTER TASK TASK_INGESTA_TICKETING SUSPEND;   -- OK
ALTER TASK TASK_APLANAR_TICKETS   SUSPEND;   -- OK

  TASK_APLANAR_TICKETS     state=suspended
  TASK_INGESTA_TICKETING   state=suspended
```

> Las tasks quedan **suspendidas** después de esta evidencia para no consumir crédito
> del trial. Para la demo en vivo: `SYSTEM$TASK_DEPENDENTS_ENABLE(...)` las reactiva de
> un golpe y `EXECUTE TASK` dispara sin esperar a las 05:00.
