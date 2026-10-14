with base as (
    select
        zone_id, full_date, request_hour,
        count(*)                               as request_count,
        count(distinct driver_id)              as active_driver_pool,
        sum(case when is_completed then 1 else 0 end) as completed_count
    from {{ ref('fact_trip') }}
    group by 1, 2, 3
),
scored as (
    select *,
        request_count * 1.0 / nullif(active_driver_pool, 0) as demand_pressure,
        1 - (completed_count * 1.0 / nullif(request_count, 0)) as unmet_rate
    from base
)
select *,
    -- min-max normalise both components 0–1, then combine 50/50
    (demand_pressure - min(demand_pressure) over()) /
        nullif(max(demand_pressure) over() - min(demand_pressure) over(), 0) * 0.5
    +
    (unmet_rate - min(unmet_rate) over()) /
        nullif(max(unmet_rate) over() - min(unmet_rate) over(), 0) * 0.5
    as under_service_index
from scored