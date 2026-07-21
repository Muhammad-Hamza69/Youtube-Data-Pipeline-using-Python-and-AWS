{#
  Ported DQ check: null percentage per column, threshold-based (was
  check_null_percentage in the old data_quality/dq_lambda.py, DQ_MAX_NULL_PERCENT
  env var, default 5%). dbt-core's built-in `not_null` test is 0%-tolerance
  only — there's no equivalent generic test in dbt-core or dbt_expectations
  for "fail if more than X% of rows are null in this column", so this is a
  direct SQL port of the original pandas logic rather than a package test.

  A dbt generic test "fails" when its query returns any rows — this returns
  exactly one row (with the actual percentage) when the threshold is
  exceeded, and zero rows otherwise.
#}
{% test test_null_percentage(model, column_name, threshold=5) %}

with stats as (
    select
        count(*) as total_rows,
        count(*) filter (where {{ column_name }} is null) as null_rows
    from {{ model }}
)

select
    total_rows,
    null_rows,
    (null_rows * 100.0 / nullif(total_rows, 0)) as null_percentage
from stats
where (null_rows * 100.0 / nullif(total_rows, 0)) > {{ threshold }}

{% endtest %}
