{{
  config(
    table_type='iceberg',
    format='parquet',
    s3_data_naming='table_unique',
    partitioned_by=['region'],
  )
}}

-- Ported from silver_to_gold_analytics.py's category_analytics aggregation.
-- view_share_pct mirrors the old PySpark Window.partitionBy(region, date) total.

with joined as (

    select
        s.region,
        s.trending_date_parsed,
        s.category_id,
        coalesce(c.category_name, 'Unknown') as category_name,
        s.video_id,
        s.views
    from {{ ref('curated_statistics') }} s
    left join {{ ref('curated_reference_data') }} c
        on s.category_id = c.id and s.region = c.region

),

agg as (

    select
        region,
        trending_date_parsed,
        category_id,
        category_name,
        count(distinct video_id) as total_videos,
        sum(views)               as total_views
    from joined
    group by region, trending_date_parsed, category_id, category_name

)

select
    *,
    total_views * 100.0 / sum(total_views) over (partition by region, trending_date_parsed) as view_share_pct
from agg
