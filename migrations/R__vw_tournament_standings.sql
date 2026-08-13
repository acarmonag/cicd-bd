-- Vista repetible: clasificación de equipos por torneo.
-- Calcula PJ, G, E, P y puntos (3 por victoria, 1 por empate).

CREATE OR REPLACE VIEW vw_tournament_standings AS
SELECT
    t.id                                                      AS tournament_id,
    t.name                                                    AS tournament,
    tm.id                                                     AS team_id,
    tm.name                                                   AS team,
    COUNT(m.id)                                               AS matches_played,
    COUNT(CASE
        WHEN (m.home_team_id = tm.id AND ms.home_score > ms.away_score)
          OR (m.away_team_id = tm.id AND ms.away_score > ms.home_score)
        THEN 1 END)                                           AS wins,
    COUNT(CASE
        WHEN ms.home_score = ms.away_score
        THEN 1 END)                                           AS draws,
    COUNT(CASE
        WHEN (m.home_team_id = tm.id AND ms.home_score < ms.away_score)
          OR (m.away_team_id = tm.id AND ms.away_score < ms.home_score)
        THEN 1 END)                                           AS losses,
    COUNT(CASE
        WHEN (m.home_team_id = tm.id AND ms.home_score > ms.away_score)
          OR (m.away_team_id = tm.id AND ms.away_score > ms.home_score)
        THEN 1 END) * 3
    + COUNT(CASE WHEN ms.home_score = ms.away_score THEN 1 END) AS points
FROM tournaments t
JOIN matches m      ON m.tournament_id = t.id
JOIN teams   tm     ON tm.id = m.home_team_id OR tm.id = m.away_team_id
LEFT JOIN match_scores ms ON ms.match_id = m.id
WHERE m.status = 'finished'
GROUP BY t.id, t.name, tm.id, tm.name
ORDER BY t.id, points DESC, wins DESC;
