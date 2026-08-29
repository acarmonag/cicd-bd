-- Pregunta de negocio: ¿Cuál es el desempeño de cada equipo por torneo?
-- Grano: una fila por (equipo, torneo).
-- Fuentes: stg_matches + stg_match_scores + stg_teams + stg_tournaments
--          (todas relacionales — capas del Medallón vía ref()).
with matches as (
    select * from {{ ref('stg_matches') }}
),

scores as (
    select * from {{ ref('stg_match_scores') }}
),

teams as (
    select * from {{ ref('stg_teams') }}
),

tournaments as (
    select * from {{ ref('stg_tournaments') }}
),

-- Expande cada partido en dos filas: una por equipo participante.
-- Solo partidos finalizados tienen marcador — los scheduled/in_progress
-- no aportan puntos todavía.
partidos_por_equipo as (
    select
        m.match_id,
        m.tournament_id,
        m.home_team_id    as team_id,
        s.goles_local     as goles_favor,
        s.goles_visitante as goles_contra
    from matches m
    inner join scores s on m.match_id = s.match_id
    where m.status = 'finished'

    union all

    select
        m.match_id,
        m.tournament_id,
        m.away_team_id    as team_id,
        s.goles_visitante as goles_favor,
        s.goles_local     as goles_contra
    from matches m
    inner join scores s on m.match_id = s.match_id
    where m.status = 'finished'
),

clasificacion as (
    select
        tournament_id,
        team_id,
        count(*)                                                        as partidos_jugados,
        sum(case when goles_favor > goles_contra  then 1 else 0 end)   as victorias,
        sum(case when goles_favor = goles_contra  then 1 else 0 end)   as empates,
        sum(case when goles_favor < goles_contra  then 1 else 0 end)   as derrotas,
        sum(goles_favor)                                                as goles_favor,
        sum(goles_contra)                                               as goles_contra,
        sum(goles_favor) - sum(goles_contra)                            as diferencia_goles,
        sum(
            case
                when goles_favor > goles_contra then 3
                when goles_favor = goles_contra then 1
                else 0
            end
        )                                                               as puntos
    from partidos_por_equipo
    group by tournament_id, team_id
)

select
    c.tournament_id,
    t.nombre_torneo,
    t.temporada,
    t.formato,
    c.team_id,
    e.nombre_equipo,
    e.ciudad,
    c.partidos_jugados,
    c.victorias,
    c.empates,
    c.derrotas,
    c.goles_favor,
    c.goles_contra,
    c.diferencia_goles,
    c.puntos,
    round(c.victorias::float / nullif(c.partidos_jugados, 0) * 100, 1) as pct_victorias,
    row_number() over (
        partition by c.tournament_id
        order by c.puntos desc, c.diferencia_goles desc, c.goles_favor desc
    ) as posicion
from clasificacion c
inner join teams e on c.team_id = e.team_id
inner join tournaments t on c.tournament_id = t.tournament_id
