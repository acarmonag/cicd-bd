-- Desnormaliza las órdenes de TicketAndes: de una fila por ORDEN (con el array
-- de boletas en VARIANT) a una fila por BOLETA, lista para sumas y conteos.
-- Este modelo es el único punto donde se usa LATERAL FLATTEN en el proyecto;
-- los modelos Gold consumen stg_ventas_tickets vía ref() sin tocar JSON crudo.
with source as (
    select
        RAW_DATA,
        ARCHIVO,
        CARGADO_EN
    from {{ source('raw_json', 'raw_ticketing') }}
),

flattened as (
    select
        source.RAW_DATA:order_id::varchar           as order_id,
        source.RAW_DATA:provider::varchar           as proveedor,
        source.RAW_DATA:purchased_at::timestamp_ntz as comprada_en,
        source.RAW_DATA:channel::varchar            as canal,
        source.RAW_DATA:match.match_id::integer     as match_id,
        source.RAW_DATA:match.external_ref::varchar as partido_ref,
        source.RAW_DATA:buyer.full_name::varchar    as comprador_nombre,
        source.RAW_DATA:buyer.email::varchar        as comprador_email,
        source.RAW_DATA:buyer.phone::varchar        as comprador_telefono,
        source.RAW_DATA:buyer.document_id::varchar  as comprador_documento,
        source.RAW_DATA:payment.method::varchar     as metodo_pago,
        source.RAW_DATA:payment.total_usd::float    as total_orden_usd,
        source.RAW_DATA:payment.installments::integer as cuotas,
        boleta.value:ticket_code::varchar           as ticket_code,
        boleta.value:category::varchar              as categoria,
        boleta.value:section::varchar               as seccion,
        boleta.value:row::varchar                   as fila,
        boleta.value:seat::integer                  as asiento,
        boleta.value:price_usd::float               as precio_usd,
        source.ARCHIVO                              as archivo_origen,
        source.CARGADO_EN                           as cargado_en
    from source,
         lateral flatten(input => source.RAW_DATA:tickets) boleta
)

select * from flattened
