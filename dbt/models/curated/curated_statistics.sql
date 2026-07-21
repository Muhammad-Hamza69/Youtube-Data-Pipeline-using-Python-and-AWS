{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['video_id', 'region', 'trending_date_parsed'],
    table_type='iceberg',
    format='parquet',
    s3_data_naming='table_unique',
    partitioned_by=['region'],
    on_schema_change='append_new_columns',
  )
}}

-- Cleaning/dedup logic ported from the old bronze_to_silver_statistics.py
-- PySpark job. Shape normalization (API vs Kaggle columns) already happened
-- upstream in the raw-transform Lambda — Raw has one stable schema, so this
-- model is pure business-logic cleaning, no source-shape branching.

with source as (

    select * from {{ source('raw', 'raw_statistics') }}
    {% if is_incremental() %}
    where _ingestion_timestamp > (
        select coalesce(max(_ingestion_timestamp), '1970-01-01T00:00:00Z') from {{ this }}
    )
    {% endif %}

),

filtered as (

    select * from source
    where video_id is not null and video_id != ''

),

normalized as (

    select
        video_id,
        title,
        channel_title,
        category_id,
        publish_time,
        lower(trim(region))                                       as region,
        source,
        case
            when source = 'youtube_api_v3'
                then date(from_iso8601_timestamp(trending_date_raw))
            when source = 'kaggle_historical'
                then date(date_parse(trending_date_raw, '%y.%d.%m'))
        end                                                        as trending_date_parsed,
        tags,
        coalesce(try_cast(views as bigint), 0)                     as views,
        coalesce(try_cast(likes as bigint), 0)                     as likes,
        try_cast(dislikes as bigint)                               as dislikes,
        coalesce(try_cast(comment_count as bigint), 0)             as comment_count,
        description,
        _ingestion_timestamp,
        _source_file
    from filtered

),

derived as (

    select
        *,
        case when views > 0 then cast(likes as double) / views else 0.0 end               as like_ratio,
        case when views > 0 then cast(likes + comment_count as double) / views else 0.0 end as engagement_rate
    from normalized
    where trending_date_parsed is not null

),

deduped as (

    select
        *,
        row_number() over (
            partition by video_id, region, trending_date_parsed
            order by _ingestion_timestamp desc
        ) as rn
    from derived

)

select
    video_id,
    title,
    channel_title,
    category_id,
    publish_time,
    region,
    source,
    trending_date_parsed,
    tags,
    views,
    likes,
    dislikes,
    comment_count,
    description,
    like_ratio,
    engagement_rate,
    _ingestion_timestamp,
    _source_file
from deduped
where rn = 1
