{{
  config(
    table_type='iceberg',
    format='parquet',
    s3_data_naming='table_unique',
    partitioned_by=['region'],
  )
}}

-- Ported from silver_to_gold_analytics.py's trending_analytics aggregation.

select
    region,
    trending_date_parsed,
    count(distinct video_id)     as total_videos,
    sum(views)                   as total_views,
    sum(likes)                   as total_likes,
    sum(comment_count)           as total_comments,
    avg(engagement_rate)         as avg_engagement_rate,
    avg(like_ratio)              as avg_like_ratio
from {{ ref('curated_statistics') }}
group by region, trending_date_parsed
