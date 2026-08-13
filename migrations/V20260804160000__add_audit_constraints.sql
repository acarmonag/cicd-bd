-- Restricciones de integridad e índices de rendimiento.

-- Un equipo no puede enfrentarse a sí mismo.
ALTER TABLE matches
    ADD CONSTRAINT chk_matches_different_teams
        CHECK (home_team_id <> away_team_id);

-- La fecha de fin del torneo debe ser posterior a su inicio.
ALTER TABLE tournaments
    ADD CONSTRAINT chk_tournaments_date_range
        CHECK (end_date > start_date);

-- Índice para filtros frecuentes por estado de partido.
CREATE INDEX idx_matches_status    ON matches (status);

-- Índice parcial para búsquedas de jugadores por posición.
CREATE INDEX idx_players_position  ON players (position) WHERE position IS NOT NULL;

-- Índice en jugadores para búsquedas por equipo + posición.
CREATE INDEX idx_players_team_position ON players (team_id, position);
