with source as (
    select * from {{ source('raw', 'match_scores') }}
),

renamed as (
    select
        ID          as score_id,
        MATCH_ID    as match_id,
        HOME_SCORE  as goles_local,
        AWAY_SCORE  as goles_visitante,
        RECORDED_AT as registrado_en
    from source
)

select * from renamed
