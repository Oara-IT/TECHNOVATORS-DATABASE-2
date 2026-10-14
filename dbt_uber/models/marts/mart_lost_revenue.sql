with avg_completed_fare as (
    select zone_id, ride_category_id, avg(total_fare_zar) as avg_fare_zar
    from {{ ref('fact_trip') }}
    where is_completed
    group by 1, 2
)
select
    f.trip_id,
    f.zone_id,
    f.ride_category_id,
    f.surge_band,
    f.is_price_cancellation,
    a.avg_fare_zar as estimated_lost_fare_zar
from {{ ref('fact_trip') }} f
join avg_completed_fare a
    on f.zone_id = a.zone_id and f.ride_category_id = a.ride_category_id
where f.is_cancelled