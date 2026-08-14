-- Eventos ocurridos durante un partido: goles, tarjetas y sustituciones.
-- Un partido tiene muchos eventos; cada evento se atribuye a un jugador.
--
-- Relación 1:N con matches — complementa a match_scores, que solo guarda
-- el marcador final. Aquí queda el detalle de cómo se llegó a ese marcador.

CREATE TABLE match_events (
    -- SERIAL: entero autoincremental. Misma convención que el resto del esquema.
    id         SERIAL    PRIMARY KEY,

    -- FK obligatoria: un evento sin partido no tiene sentido.
    match_id   INTEGER   NOT NULL REFERENCES matches (id),

    -- FK opcional (sin NOT NULL): una sustitución o un evento del cuerpo
    -- técnico no siempre se atribuye a un jugador concreto.
    player_id  INTEGER   REFERENCES players (id),

    -- Lista cerrada de valores válidos, igual que matches.status.
    -- La regla vive en la base: 'gol' o 'GOAL' son rechazados por Postgres.
    event_type TEXT      NOT NULL
                   CHECK (event_type IN ('goal', 'yellow_card', 'red_card', 'substitution')),

    -- Rango válido, igual que players.jersey_number (1-99).
    -- El tope de 130 cubre prórroga y tiempo añadido.
    minute     SMALLINT  NOT NULL CHECK (minute BETWEEN 0 AND 130),

    -- Texto libre: "penalti", "doble amarilla", "entra por lesión".
    detail     TEXT,

    -- Rastro de auditoría: cuándo se cargó el dato (no cuándo ocurrió).
    -- Mismo patrón que match_scores.recorded_at.
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

-- Índices sobre las dos claves foráneas: Postgres NO los crea solo,
-- y sin ellos los JOIN contra matches y players hacen scan completo.
CREATE INDEX idx_match_events_match_id  ON match_events (match_id);
CREATE INDEX idx_match_events_player_id ON match_events (player_id);

-- Índice PARCIAL: indexa solo las filas de goles, no toda la tabla.
-- Mismo patrón que idx_players_position. Más pequeño y más rápido
-- porque los goles son el evento que más se consulta.
CREATE INDEX idx_match_events_goals ON match_events (match_id) WHERE event_type = 'goal';
