-- Marcadores de partidos finalizados.
-- Relación 1:1 con matches — un partido tiene como máximo un marcador final.

CREATE TABLE match_scores (
    id          SERIAL   PRIMARY KEY,
    match_id    INTEGER  NOT NULL UNIQUE REFERENCES matches (id),
    home_score  SMALLINT NOT NULL DEFAULT 0 CHECK (home_score >= 0),
    away_score  SMALLINT NOT NULL DEFAULT 0 CHECK (away_score >= 0),
    recorded_at TIMESTAMP NOT NULL DEFAULT now()
);
