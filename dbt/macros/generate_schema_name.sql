{#
  Standard override: dbt's default generate_schema_name macro concatenates
  target.schema + '_' + custom_schema_name (e.g. "curated_yt_pipeline_enriched_db"),
  which is wrong here — each model's +schema config in dbt_project.yml is
  already a full, literal Glue database name (yt_pipeline_curated_db,
  yt_pipeline_enriched_db), not a suffix. Returning it directly is the
  well-known pattern for projects that map dbt "schemas" onto multiple real
  physical databases/catalogs.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
