{{
  config(
    table_type='iceberg',
    format='parquet',
    s3_data_naming='table_unique',
    partitioned_by=['region'],
  )
}}

-- Ported from silver_to_gold_analytics.py's channel_analytics aggregation.
-- rank_in_region / categories mirror the old PySpark Window + collect_set.

with agg as (

    select
        s.channel_title,
        s.region,
        count(distinct s.video_id)                                      as total_videos,
        sum(s.views)                                                    as total_views,
        avg(s.engagement_rate)                                          as avg_engagement_rate,
        array_agg(distinct coalesce(c.category_name, 'Unknown'))        as categories
    from {{ ref('curated_statistics') }} s
    left join {{ ref('curated_reference_data') }} c
        on s.category_id = c.id and s.region = c.region
    where s.channel_title is not null
    group by s.channel_title, s.region

)

select
    *,
    row_number() over (partition by region order by total_views desc) as rank_in_region
from agg
