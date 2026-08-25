"""
Datos de demostración para la base transaccional del torneo (Neon, branch dev).

El Momento 1 dejó el esquema versionado con Flyway pero sin datos operativos.
Este script puebla las 9 tablas con una temporada coherente de la "Liga
Metropolitana de Fútbol 2026": 6 equipos, 72 jugadores, 15 partidos de liga
(todos contra todos) más una copa en curso, con marcadores y eventos
consistentes entre sí (los goles de match_events suman el marcador de
match_scores).

Determinista a propósito (random.seed fijo): correrlo dos veces produce el
mismo dataset, y solo inserta si las tablas están vacías.

Uso:
    uv run seed_neon.py
"""

from __future__ import annotations

import itertools
import os
import random
import sys
from datetime import date, datetime, timedelta

import psycopg2
from dotenv import load_dotenv

random.seed(2026)

NOMBRES = [
    "Juan", "Camilo", "Andrés", "Santiago", "Mateo", "Samuel", "Daniel",
    "Sebastián", "Nicolás", "Alejandro", "David", "Miguel", "Tomás", "Julián",
    "Esteban", "Felipe", "Simón", "Emiliano", "Jerónimo", "Martín", "Diego",
    "Lucas", "Gabriel", "Thiago", "Bruno", "Facundo", "Enzo", "Kevin",
]
APELLIDOS = [
    "García", "Rodríguez", "Martínez", "López", "Hernández", "González",
    "Pérez", "Sánchez", "Ramírez", "Torres", "Flórez", "Castro", "Vargas",
    "Rojas", "Moreno", "Gutiérrez", "Ortiz", "Cardona", "Zapata", "Mesa",
    "Restrepo", "Quintero", "Valencia", "Ospina", "Montoya", "Arango",
]
NACIONALIDADES = ["Colombia"] * 8 + ["Argentina", "Brasil", "Uruguay", "Venezuela", "Ecuador"]
POSICIONES = ["GK", "DF", "DF", "DF", "MF", "MF", "MF", "FW", "FW", "DF", "MF", "FW"]

SPORTS = [
    ("Fútbol", "team"),
    ("Baloncesto", "team"),
    ("Tenis", "individual"),
]

VENUES = [
    ("Estadio Atanasio Girardot", "Medellín", "Colombia", 45943),
    ("Estadio El Campín", "Bogotá", "Colombia", 39512),
    ("Estadio Pascual Guerrero", "Cali", "Colombia", 33130),
    ("Estadio Hernán Ramírez Villegas", "Pereira", "Colombia", 30297),
]

TEAMS = [
    ("Leones de Medellín", "Medellín", 1947),
    ("Cóndores de Bogotá", "Bogotá", 1951),
    ("Tiburones de Cali", "Cali", 1949),
    ("Pumas de Pereira", "Pereira", 1963),
    ("Águilas de Bucaramanga", "Bucaramanga", 1958),
    ("Zorros de Manizales", "Manizales", 1961),
]

REFEREES = [
    ("Wilmar", "Roldán", "Colombia", date(2008, 3, 15)),
    ("Andrés", "Rojas", "Colombia", date(2012, 6, 20)),
    ("Carlos", "Ortega", "Colombia", date(2014, 9, 10)),
    ("Jhon", "Ospina", "Colombia", date(2016, 2, 5)),
    ("Bismark", "Santiago", "Panamá", date(2015, 11, 30)),
    ("Esteban", "Ostojich", "Uruguay", date(2013, 4, 18)),
]


def tablas_vacias(cur) -> bool:
    cur.execute("SELECT count(*) FROM sports")
    return cur.fetchone()[0] == 0


def main() -> int:
    load_dotenv()
    url = os.getenv("NEON_DEV_DATABASE_URL")
    if not url:
        print("ERROR: falta NEON_DEV_DATABASE_URL en .env", file=sys.stderr)
        return 1

    con = psycopg2.connect(url)
    cur = con.cursor()

    if not tablas_vacias(cur):
        print("Las tablas ya tienen datos — no se inserta nada.")
        con.close()
        return 0

    # --- catálogos -----------------------------------------------------------
    for nombre, tipo in SPORTS:
        cur.execute("INSERT INTO sports (name, type) VALUES (%s, %s)", (nombre, tipo))
    cur.execute("SELECT id FROM sports WHERE name = 'Fútbol'")
    futbol_id = cur.fetchone()[0]

    venue_ids = []
    for v in VENUES:
        cur.execute(
            "INSERT INTO venues (name, city, country, capacity) VALUES (%s, %s, %s, %s) RETURNING id",
            v,
        )
        venue_ids.append(cur.fetchone()[0])

    team_ids = []
    for nombre, ciudad, fundado in TEAMS:
        cur.execute(
            "INSERT INTO teams (name, city, sport_id, founded_year) VALUES (%s, %s, %s, %s) RETURNING id",
            (nombre, ciudad, futbol_id, fundado),
        )
        team_ids.append(cur.fetchone()[0])

    # --- jugadores: 12 por equipo, dorsales únicos dentro del equipo ---------
    plantillas: dict[int, list[int]] = {}
    for team_id in team_ids:
        plantillas[team_id] = []
        dorsales = random.sample(range(1, 100), 12)
        for posicion, dorsal in zip(POSICIONES, dorsales):
            nacimiento = date(1994, 1, 1) + timedelta(days=random.randint(0, 365 * 12))
            cur.execute(
                """INSERT INTO players
                   (first_name, last_name, team_id, position, jersey_number, birth_date, nationality)
                   VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                (
                    random.choice(NOMBRES),
                    random.choice(APELLIDOS),
                    team_id,
                    posicion,
                    dorsal,
                    nacimiento,
                    random.choice(NACIONALIDADES),
                ),
            )
            plantillas[team_id].append(cur.fetchone()[0])

    for arbitro in REFEREES:
        cur.execute(
            "INSERT INTO referees (first_name, last_name, nationality, certified_at) VALUES (%s, %s, %s, %s)",
            arbitro,
        )
    cur.execute("SELECT id FROM referees ORDER BY id")
    referee_ids = [r[0] for r in cur.fetchall()]

    # --- torneos --------------------------------------------------------------
    cur.execute(
        """INSERT INTO tournaments (name, sport_id, season, start_date, end_date, format)
           VALUES (%s, %s, %s, %s, %s, %s) RETURNING id""",
        ("Liga Metropolitana de Fútbol", futbol_id, "2026-I", date(2026, 2, 7), date(2026, 6, 27), "league"),
    )
    liga_id = cur.fetchone()[0]
    cur.execute(
        """INSERT INTO tournaments (name, sport_id, season, start_date, end_date, format)
           VALUES (%s, %s, %s, %s, %s, %s) RETURNING id""",
        ("Copa Metropolitana", futbol_id, "2026-II", date(2026, 7, 18), date(2026, 11, 28), "cup"),
    )
    copa_id = cur.fetchone()[0]

    # --- liga: todos contra todos (15 partidos), todos finalizados ------------
    fecha = datetime(2026, 2, 7, 15, 30)
    for local, visitante in itertools.combinations(team_ids, 2):
        _crear_partido(cur, plantillas, liga_id, local, visitante,
                       random.choice(venue_ids), random.choice(referee_ids),
                       fecha, estado="finished")
        fecha += timedelta(days=9, hours=random.choice([0, 2, 4]))

    # --- copa: primera fase en curso ------------------------------------------
    fecha = datetime(2026, 7, 18, 19, 0)
    emparejamientos = [
        (team_ids[0], team_ids[3], "finished"),
        (team_ids[1], team_ids[4], "finished"),
        (team_ids[2], team_ids[5], "in_progress"),
        (team_ids[0], team_ids[1], "scheduled"),
    ]
    for local, visitante, estado in emparejamientos:
        _crear_partido(cur, plantillas, copa_id, local, visitante,
                       random.choice(venue_ids), random.choice(referee_ids),
                       fecha, estado=estado)
        fecha += timedelta(days=7)

    con.commit()

    for tabla in ["sports", "venues", "teams", "players", "tournaments",
                  "referees", "matches", "match_scores", "match_events"]:
        cur.execute(f"SELECT count(*) FROM {tabla}")
        print(f"  {tabla}: {cur.fetchone()[0]} filas")
    con.close()
    print("Seed completado.")
    return 0


def _crear_partido(cur, plantillas, torneo_id, local, visitante, venue_id,
                   referee_id, cuando, estado):
    cur.execute(
        """INSERT INTO matches
           (tournament_id, home_team_id, away_team_id, venue_id, referee_id, scheduled_at, status)
           VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id""",
        (torneo_id, local, visitante, venue_id, referee_id, cuando, estado),
    )
    match_id = cur.fetchone()[0]

    if estado != "finished":
        return

    goles_local = random.randint(0, 4)
    goles_visitante = random.randint(0, 3)
    cur.execute(
        """INSERT INTO match_scores (match_id, home_score, away_score, recorded_at)
           VALUES (%s, %s, %s, %s)""",
        (match_id, goles_local, goles_visitante, cuando + timedelta(hours=2)),
    )

    # Los goles de match_events deben sumar exactamente el marcador final.
    minutos = random.sample(range(1, 91), goles_local + goles_visitante + 4)
    idx = 0
    for equipo, goles in ((local, goles_local), (visitante, goles_visitante)):
        for _ in range(goles):
            cur.execute(
                """INSERT INTO match_events (match_id, player_id, event_type, minute, detail)
                   VALUES (%s, %s, 'goal', %s, %s)""",
                (match_id, random.choice(plantillas[equipo][7:]), minutos[idx],
                 random.choice(["jugada colectiva", "penalti", "tiro libre", "cabezazo", None])),
            )
            idx += 1

    # Tarjetas y sustituciones para que el partido no sea solo goles.
    cur.execute(
        """INSERT INTO match_events (match_id, player_id, event_type, minute, detail)
           VALUES (%s, %s, 'yellow_card', %s, 'falta táctica')""",
        (match_id, random.choice(plantillas[local]), minutos[idx]),
    )
    cur.execute(
        """INSERT INTO match_events (match_id, player_id, event_type, minute, detail)
           VALUES (%s, %s, 'substitution', %s, 'entra por desgaste')""",
        (match_id, random.choice(plantillas[visitante]), minutos[idx + 1]),
    )


if __name__ == "__main__":
    sys.exit(main())
