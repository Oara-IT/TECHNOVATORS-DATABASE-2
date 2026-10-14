select
    t.trip_id,
    t.rider_id,
    t.driver_id,
    t.zone_id,
    t.ride_category_id,
    date(t.request_timestamp)              as full_date,
    extract(hour from t.request_timestamp) as request_hour,
    t.trip_status_id,
    t.cancellation_reason_id,
    f.distance_km,
    f.duration_minutes,
    f.surge_multiplier,
    f.total_fare_zar,
    f.platform_commission_zar,
    f.driver_payout_zar,
    f.payment_method_id,

    -- flags used directly by DAX, computed once here for consistency
    ts.trip_status_name = 'Completed'                     as is_completed,
    ts.trip_status_name = 'Cancelled'                      as is_cancelled,
    cr.cancellation_reason_name = 'PRICING_SURGE'           as is_price_cancellation,
    f.surge_multiplier > 1.0                                as is_surged,
    case
        when f.surge_multiplier = 1.0 then '1.0x (no surge)'
        when f.surge_multiplier <= 1.5 then '1.1x–1.5x'
        when f.surge_multiplier <= 2.0 then '1.6x–2.0x'
        else '2.0x+'
    end as surge_band

from {{ source('raw', 'trip') }} t
join {{ source('raw', 'trip_fare') }} f on t.trip_id = f.trip_id
left join {{ source('raw', 'trip_status') }} ts on t.trip_status_id = ts.trip_status_id
left join {{ source('raw', 'cancellation_reason') }} cr on t.cancellation_reason_id = cr.cancellation_reason_id