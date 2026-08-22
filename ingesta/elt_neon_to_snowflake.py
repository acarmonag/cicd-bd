"""
ELT relacional: Neon (PostgreSQL) -> Snowflake, capa RAW.

Momento 2 — proyecto Torneos Deportivos.

Extrae las tablas del sistema de torneos desde la branch `dev` de Neon (la misma
base versionada con Flyway en el Momento 1) y las carga, sin transformar, en el
schema RAW de TORNEOS_DB. Es "ELT", no "ETL": la transformación ocurre después,
dentro del warehouse — no aquí.

Uso:
    uv run elt_neon_to_snowflake.py                   # carga las 9 tablas
    uv run elt_neon_to_snowflake.py --tabla matches   # solo una tabla
    uv run elt_neon_to_snowflake.py --solo-verificar  # detecta drift, no carga
"""

from __future__ import annotations

import argparse
import os
import sys

import pandas as pd
import psycopg2
import snowflake.connector
from dotenv import load_dotenv
from snowflake.connector.pandas_tools import write_pandas

# Las 9 tablas del modelo transaccional del Momento 1 (repositorio cicd-bd,
# migraciones Flyway V20260801..V20260814). La vista vw_tournament_standings
# no se extrae: las vistas se reconstruyen en el warehouse, no se copian.
TABLAS = [
    "sports",
    "venues",
    "teams",
    "players",
    "tournaments",
    "referees",
    "matches",
    "match_scores",
    "match_events",
]

# Mapeo deliberadamente aproximado de dtypes de pandas a tipos de Snowflake.
# El tipado fino es trabajo de capas posteriores (dbt, Momento 3) — la capa RAW
# solo necesita no perder información ni renunciar a toda validación.
MAPA_TIPOS_SNOWFLAKE = {
    "int64": "NUMBER",
    "float64": "FLOAT",
    "bool": "BOOLEAN",
    "datetime64[ns]": "TIMESTAMP_NTZ",
    "object": "VARCHAR",
}


# ---------------------------------------------------------------------------
# Extracción — Neon
# ---------------------------------------------------------------------------

def conectar_neon() -> psycopg2.extensions.connection:
    url = os.getenv("NEON_DEV_DATABASE_URL")
    if not url:
        print("ERROR: falta NEON_DEV_DATABASE_URL en .env", file=sys.stderr)
        sys.exit(1)
    return psycopg2.connect(url)


def extraer_tabla(conexion_pg, tabla: str) -> pd.DataFrame:
    # SELECT * a propósito: la extracción no sabe nada del negocio. Si el equipo
    # de backend agrega una columna en Neon, la extracción la recoge sola — y la
    # detección de drift (abajo) decide qué hacer con ella antes de cargar.
    with conexion_pg.cursor() as cursor:
        cursor.execute(f"SELECT * FROM {tabla}")
        # Snowflake guarda identificadores sin comillas en MAYÚSCULA. Normalizar
        # aquí evita que la comparación de schemas crea que todo es drift.
        columnas = [c.name.upper() for c in cursor.description]
        filas = cursor.fetchall()
    return pd.DataFrame(filas, columns=columnas)


# ---------------------------------------------------------------------------
# Detección de schema drift — lógica pura, sin I/O
# ---------------------------------------------------------------------------

def calcular_drift(columnas_dataframe: set[str], columnas_snowflake: set[str]) -> set[str]:
    """Columnas que trae la extracción y que la tabla destino todavía no tiene."""
    return columnas_dataframe - columnas_snowflake


def construir_ddl_evolucion(tabla: str, columnas_nuevas: set[str], df: pd.DataFrame) -> str:
    """Genera el ALTER TABLE que resolvería el drift — para mostrarlo, no para ejecutarlo solo."""
    lineas = []
    for columna in sorted(columnas_nuevas):
        tipo_pandas = str(df[columna].dtype)
        tipo_snowflake = MAPA_TIPOS_SNOWFLAKE.get(tipo_pandas, "VARCHAR")
        lineas.append(f'ALTER TABLE {tabla.upper()} ADD COLUMN "{columna}" {tipo_snowflake};')
    return "\n".join(lineas)


# ---------------------------------------------------------------------------
# Snowflake — I/O
# ---------------------------------------------------------------------------

def conectar_snowflake() -> snowflake.connector.SnowflakeConnection:
    # Warehouse/database/schema/role explícitos: cada sentencia corre en el
    # contexto de la sesión activa. Dejarlo implícito hace que el script
    # funcione en la máquina de quien configuró defaults y falle en la del
    # resto del equipo — exactamente lo que este momento prohíbe.
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=os.environ.get("SNOWFLAKE_SCHEMA", "RAW"),
        role=os.environ.get("SNOWFLAKE_ROLE"),
    )


def columnas_existentes_en_snowflake(conexion_sf, esquema: str, tabla: str) -> set[str]:
    with conexion_sf.cursor() as cursor:
        cursor.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = %s AND table_name = %s",
            (esquema.upper(), tabla.upper()),
        )
        return {fila[0] for fila in cursor.fetchall()}


def cargar_tabla(conexion_sf, tabla: str, df: pd.DataFrame, esquema: str) -> int:
    existentes = columnas_existentes_en_snowflake(conexion_sf, esquema, tabla)

    if existentes:
        drift = calcular_drift(set(df.columns), existentes)
        if drift:
            # Fallar aquí, con mensaje propio y el DDL ya redactado, es mejor
            # que dejar que write_pandas explote tres capas más abajo con un
            # "invalid identifier" que no dice tabla, columna, ni qué hacer.
            ddl = construir_ddl_evolucion(tabla, drift, df)
            raise RuntimeError(
                f"\nSchema drift detectado en {tabla.upper()}: la fuente en Neon trae "
                f"columna(s) nueva(s) que Snowflake no tiene todavía: {sorted(drift)}.\n\n"
                f"Aplica esto en un Worksheet de Snowsight y vuelve a correr el script:\n\n"
                f"{ddl}\n"
            )

    exito, _, num_filas, _ = write_pandas(
        conexion_sf,
        df,
        table_name=tabla.upper(),
        auto_create_table=True,
        overwrite=True,
    )
    if not exito:
        raise RuntimeError(f"write_pandas reportó fallo al cargar {tabla}")
    return num_filas


# ---------------------------------------------------------------------------
# Orquestación
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="ELT del sistema de torneos: Neon -> capa RAW de Snowflake."
    )
    parser.add_argument("--tabla", choices=TABLAS, help="Cargar solo esta tabla.")
    parser.add_argument(
        "--solo-verificar",
        action="store_true",
        help="Extrae y compara schemas, pero no escribe nada en Snowflake.",
    )
    argumentos = parser.parse_args()

    load_dotenv()
    tablas = [argumentos.tabla] if argumentos.tabla else TABLAS
    esquema = os.environ.get("SNOWFLAKE_SCHEMA", "RAW")

    conexion_pg = conectar_neon()
    conexion_sf = conectar_snowflake()
    try:
        for tabla in tablas:
            print(f"Extrayendo {tabla} desde Neon...")
            df = extraer_tabla(conexion_pg, tabla)
            print(f"  {len(df)} filas · columnas: {list(df.columns)}")

            if argumentos.solo_verificar:
                existentes = columnas_existentes_en_snowflake(conexion_sf, esquema, tabla)
                drift = calcular_drift(set(df.columns), existentes) if existentes else set()
                estado = f"DRIFT: {sorted(drift)}" if drift else "sin drift"
                print(f"  [verificación] {estado}")
                continue

            num_filas = cargar_tabla(conexion_sf, tabla, df, esquema)
            print(f"  OK -> {num_filas} filas en {esquema}.{tabla.upper()}")

        return 0
    except RuntimeError as error:
        print(f"\nERROR: {error}", file=sys.stderr)
        return 1
    finally:
        conexion_pg.close()
        conexion_sf.close()


if __name__ == "__main__":
    sys.exit(main())
