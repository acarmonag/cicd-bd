-- Sobrescribe el macro por defecto de dbt para que el valor de +schema en
-- dbt_project.yml se use directamente como nombre del schema en Snowflake,
-- sin concatenar el schema por defecto del perfil.
--
-- Sin este macro: +schema: STAGING con target.schema: RAW → TORNEOS_DB.RAW_STAGING
-- Con este macro: +schema: STAGING                       → TORNEOS_DB.STAGING
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | upper }}
    {%- else -%}
        {{ custom_schema_name | upper }}
    {%- endif -%}
{%- endmacro %}
