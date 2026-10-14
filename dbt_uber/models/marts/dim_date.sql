with bounds as (
    select min(date(request_timestamp)) as min_d, max(date(request_timestamp)) as max_d
    from {{ source('raw', 'trip') }}
)

select
    d as full_date,
    extract(dayofweek from d) - 1 as day_of_week, -- 0=Sun
    format_date('%A', d) as day_name,
    extract(dayofweek from d) in (1, 7) as is_weekend,
    extract(day from d) >= 25 as is_month_end,
    extract(month from d) as month_num,
    format_date('%B', d) as month_name
    -- public_holiday / academic_term flags: TODO once the supplementary
    -- calendar (RQ6) is sourced and loaded as a seed table

from bounds, unnest(generate_date_array(bounds.min_d, bounds.max_d)) as d