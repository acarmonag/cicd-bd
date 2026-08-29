with source as (
    select * from {{ source('raw', 'tournaments') }}
),

renamed as (
    select
        ID         as tournament_id,
        NAME       as nombre_torneo,
        SPORT_ID   as sport_id,
        SEASON     as temporada,
        START_DATE as fecha_inicio,
        END_DATE   as fecha_fin,
        FORMAT     as formato
    from source
)

select * from renamed
