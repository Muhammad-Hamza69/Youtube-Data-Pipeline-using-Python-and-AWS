{{
  config(
    materialized='table',
    table_type='iceberg',
    format='parquet',
    s3_data_naming='table_unique',
  )
}}

-- Full-refresh (not incremental) — reference data is small and rarely
-- changes; dedup ported from the old validate_category_data() (keep last).

with source as (
    select * from {{ source('raw', 'raw_reference_data') }}
    where id is not null
),

deduped as (
    select
        *,
        row_number() over (
            partition by id, region
            order by _ingestion_timestamp desc
        ) as rn
    from source
)

select
    id,
    title as category_name,
    region,
    _ingestion_timestamp,
    _source_file
from deduped
where rn = 1
