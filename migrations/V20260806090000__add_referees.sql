-- Agrega árbitros a los partidos del torneo.

CREATE TABLE referees (
    id           SERIAL PRIMARY KEY,
    first_name   TEXT   NOT NULL,
    last_name    TEXT   NOT NULL,
    nationality  TEXT   NOT NULL,
    certified_at DATE
);

ALTER TABLE matches ADD COLUMN referee_id INTEGER REFERENCES referees (id);

CREATE INDEX idx_matches_referee_id ON matches (referee_id);
