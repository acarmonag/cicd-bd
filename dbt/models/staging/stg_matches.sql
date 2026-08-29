with source as (
    select * from {{ source('raw', 'matches') }}
),

renamed as (
    select
        ID            as match_id,
        TOURNAMENT_ID as tournament_id,
        HOME_TEAM_ID  as home_team_id,
        AWAY_TEAM_ID  as away_team_id,
        VENUE_ID      as venue_id,
        REFEREE_ID    as referee_id,
        SCHEDULED_AT  as scheduled_at,
        STATUS        as status
    from source
)

select * from renamed
