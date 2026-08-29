-- Pregunta de negocio: ¿Cuánto recaudó cada partido en venta de tickets
-- y cuántas boletas se emitieron por categoría?
-- Grano: una fila por (partido, categoría de ticket).
--
-- CRUZA DOS FUENTES DISTINTAS:
--   stg_ventas_tickets → origen semi-estructurado (JSON de TicketAndes, RAW_JSON)
--   stg_matches + stg_teams → origen relacional (Neon PostgreSQL, RAW)
-- El punto de unión es match_id, que el proveedor registró al crear el evento.
with tickets as (
    select * from {{ ref('stg_ventas_tickets') }}
),

matches as (
    select * from {{ ref('stg_matches') }}
),

teams as (
    select * from {{ ref('stg_teams') }}
),

recaudo_por_partido_categoria as (
    select
        match_id,
        categoria,
        count(distinct order_id) as total_ordenes,
        count(ticket_code)       as total_boletas,
        sum(precio_usd)          as total_usd,
        avg(precio_usd)          as precio_promedio_usd
    from tickets
    group by match_id, categoria
)

select
    r.match_id,
    m.scheduled_at                  as fecha_partido,
    m.status                        as estado_partido,
    local_team.nombre_equipo        as equipo_local,
    local_team.ciudad               as ciudad_local,
    visitante_team.nombre_equipo    as equipo_visitante,
    visitante_team.ciudad           as ciudad_visitante,
    r.categoria,
    r.total_ordenes,
    r.total_boletas,
    r.total_usd,
    r.precio_promedio_usd
from recaudo_por_partido_categoria r
inner join matches m on r.match_id = m.match_id
inner join teams local_team on m.home_team_id = local_team.team_id
inner join teams visitante_team on m.away_team_id = visitante_team.team_id
