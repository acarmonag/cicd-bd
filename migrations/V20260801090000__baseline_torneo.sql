-- Baseline: esquema de gestión de torneos deportivos.
-- Entidades principales: deportes, recintos, equipos, jugadores y torneos.

CREATE TABLE sports (
    id   SERIAL PRIMARY KEY,
    name TEXT   NOT NULL UNIQUE,
    type TEXT   NOT NULL CHECK (type IN ('individual', 'team'))
);

CREATE TABLE venues (
    id       SERIAL  PRIMARY KEY,
    name     TEXT    NOT NULL,
    city     TEXT    NOT NULL,
    country  TEXT    NOT NULL,
    capacity INTEGER CHECK (capacity > 0)
);

CREATE TABLE teams (
    id           SERIAL   PRIMARY KEY,
    name         TEXT     NOT NULL,
    city         TEXT     NOT NULL,
    sport_id     INTEGER  NOT NULL REFERENCES sports (id),
    founded_year SMALLINT CHECK (founded_year BETWEEN 1800 AND 2100),
    logo_url     TEXT
);

CREATE TABLE players (
    id            SERIAL  PRIMARY KEY,
    first_name    TEXT    NOT NULL,
    last_name     TEXT    NOT NULL,
    team_id       INTEGER REFERENCES teams (id),
    position      TEXT,
    jersey_number SMALLINT CHECK (jersey_number BETWEEN 1 AND 99),
    birth_date    DATE,
    nationality   TEXT    NOT NULL
);

CREATE TABLE tournaments (
    id         SERIAL      PRIMARY KEY,
    name       TEXT        NOT NULL,
    sport_id   INTEGER     NOT NULL REFERENCES sports (id),
    season     VARCHAR(9)  NOT NULL,
    start_date DATE        NOT NULL,
    end_date   DATE        NOT NULL,
    format     TEXT        NOT NULL
                   CHECK (format IN ('league', 'cup', 'group_knockout'))
);

CREATE INDEX idx_teams_sport_id        ON teams       (sport_id);
CREATE INDEX idx_players_team_id       ON players     (team_id);
CREATE INDEX idx_tournaments_sport_id  ON tournaments (sport_id);
CREATE INDEX idx_tournaments_season    ON tournaments (season);
