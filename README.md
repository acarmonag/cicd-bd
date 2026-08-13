# cicd-bd — CI/CD en Base de Datos con Flyway

Módulo **Tendencias emergentes en desarrollo de software** (SI6010-5979) · Momento 1  
Stack: **Neon.tech** (PostgreSQL) · **Flyway** · **GitHub Actions**  
Dominio: Sistema de gestión de torneos deportivos

---

## Integrantes

| Nombre | GitHub |
|--------|--------|
| Antonio Carmona | [@acarmonag](https://github.com/acarmonag) |
| Miguel Quijano | [@mquijanoj09](https://github.com/mquijanoj09) |
| Andrés Prada | [@Pradita777](https://github.com/Pradita777) |

---

## Estructura del repositorio

```
cicd-bd/
├── .github/workflows/flyway-migrate.yml       # CI/CD automático
├── docs/
│   ├── evidencias/                             # Capturas de runs exitoso y fallido
│   └── dominio_negocio.md                      # Descripción + diagrama ER
├── migrations/
│   ├── V20260801070000__cleanup_legacy.sql     # Limpieza esquema previo
│   ├── V20260801090000__baseline_torneo.sql    # Esquema base completo
│   ├── V20260802100000__add_matches.sql        # Tabla matches
│   ├── V20260803143000__add_match_scores.sql   # Tabla match_scores
│   ├── V20260804160000__add_audit_constraints.sql  # CHECKs + índices
│   ├── V20260806090000__add_referees.sql       # Tabla referees + matches.referee_id
│   └── R__vw_tournament_standings.sql          # Vista repetible
├── flyway.conf.example                         # Plantilla local sin credenciales
└── README.md
```

---

## Entornos en Neon.tech

| Entorno | Branch Neon | Cuándo se aplica |
|---------|-------------|------------------|
| `dev`   | `dev`       | Pull request abierto hacia `main` |
| `prod`  | `main`      | Merge/push a `main` |

---

## Secretos requeridos en GitHub

Configura en **Settings → Secrets and variables → Actions**:

| Secreto | Descripción |
|---------|-------------|
| `FLYWAY_URL_DEV` | `jdbc:postgresql://<host>/neondb?sslmode=require` (branch dev) |
| `FLYWAY_USER_DEV` | Usuario Neon branch dev |
| `FLYWAY_PASSWORD_DEV` | Contraseña Neon branch dev |
| `FLYWAY_URL_PROD` | `jdbc:postgresql://<host>/neondb?sslmode=require` (branch main) |
| `FLYWAY_USER_PROD` | Usuario Neon branch main |
| `FLYWAY_PASSWORD_PROD` | Contraseña Neon branch main |

---

## Configuración local

### 1. Instalar Flyway CLI

```bash
# macOS
brew install flyway
```

### 2. Configurar credenciales

```bash
cp flyway.conf.example flyway.conf
# Edita flyway.conf con tus credenciales de Neon (branch dev)
# NUNCA hagas commit de flyway.conf — está en .gitignore
```

### 3. Ejecutar migraciones

```bash
flyway info        # ver estado actual
flyway migrate     # aplicar pendientes
flyway validate    # verificar checksums
```

### 4. Reconstruir desde cero (solo dev)

```bash
# Requiere cleanDisabled=false en flyway.conf
flyway clean && flyway migrate
```

---

## Cómo agregar una migración nueva

1. Crea el archivo en `migrations/` con la convención:
   - Versionada: `V{YYYYMMDDHHmmss}__{descripcion}.sql`
   - Repetible: `R__{nombre_objeto}.sql`

2. Escribe SQL atómico con un propósito único.

3. Abre un Pull Request hacia `main`.  
   El workflow ejecuta `flyway migrate` automáticamente en **DEV**.

4. Merge a `main` → migración aplicada en **PROD**.

> Nunca modifiques una migración ya aplicada (`V__`). Flyway verifica checksums y fallará.

---

## Comportamiento del workflow

| Evento | Entorno | Acciones |
|--------|---------|----------|
| PR abierto / actualizado | `dev` | validate + info + migrate |
| Push / merge a `main` | `prod` | validate + info + migrate |
| `workflow_dispatch` | elegible | operador elige `dev` o `prod` |

---

## Caso de migración fallida y corrección

Durante la validación de la migración de árbitros, la versión inicial de `V20260806090000__add_referees.sql` falló porque el nombre del objeto no coincidía con el modelo de negocio: se intentó crear una tabla `arbitros` en lugar de la entidad esperada `referees`. Ese desajuste provocó que Flyway no aplicara la migración correctamente, como se observa en la evidencia de la ejecución fallida en [docs/evidencias/migracion_fallada.png](docs/evidencias/migracion_fallada.png).

La corrección consistió en reescribir la migración para que el esquema quedara alineado con el dominio: se creó la tabla `referees` con sus columnas requeridas y luego se añadió `referee_id` a `matches` como clave foránea. Con este ajuste, la migración quedó consistente y la ejecución fue exitosa, como se muestra en [docs/evidencias/migracio_exitosa.png](docs/evidencias/migracio_exitosa.png).

La versión corregida quedó así:

```sql
CREATE TABLE referees (
    id           SERIAL PRIMARY KEY,
    first_name   TEXT   NOT NULL,
    last_name    TEXT   NOT NULL,
    nationality  TEXT   NOT NULL,
    certified_at DATE
);

ALTER TABLE matches ADD COLUMN referee_id INTEGER REFERENCES referees (id);

CREATE INDEX idx_matches_referee_id ON matches (referee_id);
```

Este ejemplo ilustra la regla principal de Flyway: si una migración falla, se debe corregir la versión en el código SQL y volver a ejecutar la validación, manteniendo la integridad del esquema y documentando el cambio para que la historia del despliegue quede clara.
