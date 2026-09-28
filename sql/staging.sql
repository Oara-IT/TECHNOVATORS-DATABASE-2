-- Raw landing tables: every column TEXT so COPY never fails on types/'N/A'.
-- Temp + ON COMMIT DROP => they vanish after the load and never appear in the ERD.
CREATE TEMP TABLE stg_zones (
    zone_id text, zone_name text, city text,
    base_fare_zar text, per_km_rate_zar text, per_min_rate_zar text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_drivers (
    driver_id text, first_name text, last_name text, operating_city text,
    platform_affiliation text, platform_commission_pct text, driver_rating text,
    total_lifetime_trips text, onboarding_date text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_trip_header (
    trip_id text, rider_id text, driver_id text, zone_id text, ride_category text,
    request_timestamp text, trip_status text, cancellation_reason text
) ON COMMIT DROP;

CREATE TEMP TABLE stg_trip_fare (
    trip_id text, distance_km text, duration_minutes text, surge_multiplier text,
    base_fare_zar text, tolls_zar text, tip_zar text, total_fare_zar text,
    platform_commission_zar text, driver_payout_zar text, payment_method text
) ON COMMIT DROP;