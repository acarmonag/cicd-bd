with source as (
    select * from {{ source('raw', 'teams') }}
),

renamed as (
    select
        ID           as team_id,
        NAME         as nombre_equipo,
        CITY         as ciudad,
        SPORT_ID     as sport_id,
        FOUNDED_YEAR as anio_fundacion,
        LOGO_URL     as logo_url
    from source
)

select * from renamed
