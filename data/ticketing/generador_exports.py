"""
Genera los exports semanales del proveedor de ticketing "TicketAndes".

La fuente es sintética (el enunciado del Momento 2 permite inventarla) pero su
forma replica lo que un proveedor real entrega: un array JSON de órdenes de
compra por archivo, con el detalle de boletas como ARRAY ANIDADO — que es lo
que justifica LATERAL FLATTEN en Snowflake — y con claves que no siempre
vienen (phone, section, installments), como pasa en cualquier webhook real.

El proveedor conoce el match_id porque el organizador del torneo registra cada
partido en la plataforma de ticketing con su propio identificador.

Determinista (random.seed fijo). Uso:
    uv --project ../../ingesta run python generador_exports.py
"""

from __future__ import annotations

import json
import random
from datetime import datetime, timedelta
from pathlib import Path

random.seed(777)

AQUI = Path(__file__).parent

NOMBRES = [
    "Laura Gómez", "Carlos Betancur", "Ana María Salazar", "Jorge Iván Ruiz",
    "Valentina Ochoa", "Pedro Pablo Mejía", "Sara Londoño", "Julián Cano",
    "Manuela Villa", "Ricardo Palacio", "Isabela Franco", "Óscar Duque",
    "Catalina Ríos", "Fernando Botero", "Luisa Echeverri", "Alejandro Marín",
    "Daniela Osorio", "Héctor Fabio Gil", "María José Toro", "Samuel Agudelo",
    "Paula Andrea Vélez", "Gustavo Henao", "Carolina Bedoya", "Mateo Zuluaga",
]

# Partidos de la Copa Metropolitana y últimas fechas de liga (ids reales del
# modelo relacional cargado en RAW — el organizador los registró en TicketAndes).
PARTIDOS = [
    {"match_id": 14, "external_ref": "LMF2026-M14", "home_team": "Pumas de Pereira",
     "away_team": "Águilas de Bucaramanga", "venue": "Estadio Hernán Ramírez Villegas",
     "kickoff": "2026-06-13T15:30:00"},
    {"match_id": 15, "external_ref": "LMF2026-M15", "home_team": "Águilas de Bucaramanga",
     "away_team": "Zorros de Manizales", "venue": "Estadio Atanasio Girardot",
     "kickoff": "2026-06-22T19:30:00"},
    {"match_id": 16, "external_ref": "CM2026-Q1", "home_team": "Leones de Medellín",
     "away_team": "Pumas de Pereira", "venue": "Estadio Atanasio Girardot",
     "kickoff": "2026-07-18T19:00:00"},
    {"match_id": 17, "external_ref": "CM2026-Q2", "home_team": "Cóndores de Bogotá",
     "away_team": "Águilas de Bucaramanga", "venue": "Estadio El Campín",
     "kickoff": "2026-07-25T19:00:00"},
    {"match_id": 18, "external_ref": "CM2026-Q3", "home_team": "Tiburones de Cali",
     "away_team": "Zorros de Manizales", "venue": "Estadio Pascual Guerrero",
     "kickoff": "2026-08-01T19:00:00"},
    {"match_id": 19, "external_ref": "CM2026-SF1", "home_team": "Leones de Medellín",
     "away_team": "Cóndores de Bogotá", "venue": "Estadio Atanasio Girardot",
     "kickoff": "2026-08-08T19:00:00"},
]

CATEGORIAS = [("general", 18.0), ("preferencial", 37.0), ("palco", 82.0)]
SECCIONES = ["Norte", "Sur", "Oriental", "Occidental"]


def generar_orden(numero: int, fecha_export: datetime) -> dict:
    partido = random.choice(PARTIDOS)
    comprada = fecha_export - timedelta(days=random.randint(1, 6),
                                        hours=random.randint(0, 23),
                                        minutes=random.randint(0, 59))
    nombre = random.choice(NOMBRES)
    usuario = nombre.lower().replace(" ", ".").replace("ó", "o").replace("é", "e") \
                            .replace("í", "i").replace("á", "a").replace("ú", "u") \
                            .replace("ñ", "n")

    boletas = []
    categoria, precio = random.choice(CATEGORIAS)
    for i in range(random.randint(1, 4)):
        boleta = {
            "ticket_code": f"TKA-{partido['external_ref']}-{numero:04d}-{i + 1}",
            "category": categoria,
            "row": random.choice("ABCDEFGHJK"),
            "seat": random.randint(1, 40),
            "price_usd": precio,
        }
        # 'section' no viene en boletas de palco — el palco ES la sección.
        if categoria != "palco":
            boleta["section"] = random.choice(SECCIONES)
        boletas.append(boleta)

    orden = {
        "order_id": f"TKA-{fecha_export:%Y%m%d}-{numero:04d}",
        "provider": "TicketAndes",
        "purchased_at": comprada.strftime("%Y-%m-%dT%H:%M:%S"),
        "channel": random.choice(["web", "app", "taquilla"]),
        "match": partido,
        "buyer": {
            "full_name": nombre,
            "email": f"{usuario}@{random.choice(['gmail.com', 'hotmail.com', 'outlook.com'])}",
            "document_id": f"CC {random.randint(10_000_000, 1_199_999_999)}",
        },
        "payment": {
            "method": random.choice(["tarjeta_credito", "pse", "efectivo"]),
            "total_usd": round(sum(b["price_usd"] for b in boletas), 2),
        },
        "tickets": boletas,
    }
    # 'phone' es opcional en la compra — ~1 de cada 3 compradores no lo da.
    if random.random() < 0.66:
        orden["buyer"]["phone"] = f"+57 3{random.randint(0, 2)}{random.randint(0, 9)} {random.randint(100, 999)} {random.randint(1000, 9999)}"
    # 'installments' solo aplica a tarjeta de crédito.
    if orden["payment"]["method"] == "tarjeta_credito":
        orden["payment"]["installments"] = random.choice([1, 1, 3, 6])
    return orden


def main() -> None:
    numero = 0
    for fecha in ["2026-08-07", "2026-08-14", "2026-08-21"]:
        fecha_export = datetime.fromisoformat(fecha + "T08:00:00")
        ordenes = []
        for _ in range(random.randint(8, 10)):
            numero += 1
            ordenes.append(generar_orden(numero, fecha_export))
        destino = AQUI / f"ticketing_export_{fecha}.json"
        destino.write_text(json.dumps(ordenes, ensure_ascii=False, indent=2) + "\n")
        total_boletas = sum(len(o["tickets"]) for o in ordenes)
        print(f"{destino.name}: {len(ordenes)} órdenes, {total_boletas} boletas")


if __name__ == "__main__":
    main()
