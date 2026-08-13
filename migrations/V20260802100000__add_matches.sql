-- Partidos: encuentros entre dos equipos dentro de un torneo.

CREATE TABLE matches (
    id            SERIAL    PRIMARY KEY,
    tournament_id INTEGER   NOT NULL REFERENCES tournaments (id),
    home_team_id  INTEGER   NOT NULL REFERENCES teams (id),
    away_team_id  INTEGER   NOT NULL REFERENCES teams (id),
    venue_id      INTEGER   REFERENCES venues (id),
    scheduled_at  TIMESTAMP NOT NULL,
    status        TEXT      NOT NULL DEFAULT 'scheduled'
                      CHECK (status IN ('scheduled', 'in_progress', 'finished', 'cancelled'))
);

CREATE INDEX idx_matches_tournament_id ON matches (tournament_id);
CREATE INDEX idx_matches_scheduled_at  ON matches (scheduled_at);
