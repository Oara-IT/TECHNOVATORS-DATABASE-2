-- Staging -> normalized tables (parents first, children last)

-- 1. lookups
INSERT INTO city (city_name)
SELECT city FROM stg_zones UNION SELECT operating_city FROM stg_drivers ORDER BY 1;

INSERT INTO platform (platform_name) VALUES ('Uber'), ('Bolt');

INSERT INTO ride_category (ride_category_name)
SELECT DISTINCT ride_category FROM stg_trip_header ORDER BY 1;

INSERT INTO trip_status (trip_status_name)
SELECT DISTINCT trip_status FROM stg_trip_header ORDER BY 1;

INSERT INTO cancellation_reason (cancellation_reason_name)
SELECT DISTINCT cancellation_reason FROM stg_trip_header
WHERE cancellation_reason IS NOT NULL AND cancellation_reason <> 'N/A' ORDER BY 1;

INSERT INTO payment_method (payment_method_name)
SELECT DISTINCT payment_method FROM stg_trip_fare ORDER BY 1;

-- 2. entities
INSERT INTO rider (rider_id)
SELECT DISTINCT rider_id FROM stg_trip_header;

INSERT INTO pricing_zone (zone_id, zone_name, city_id, base_fare_zar,
                          per_km_rate_zar, per_min_rate_zar)
SELECT z.zone_id, z.zone_name, c.city_id, z.base_fare_zar::numeric,
       z.per_km_rate_zar::numeric, z.per_min_rate_zar::numeric
FROM stg_zones z JOIN city c ON c.city_name = z.city;

INSERT INTO driver (driver_id, first_name, last_name, operating_city_id,
                    driver_rating, total_lifetime_trips, onboarding_date)
SELECT d.driver_id, d.first_name, d.last_name, c.city_id,
       d.driver_rating::numeric, d.total_lifetime_trips::int,
       TO_DATE(d.onboarding_date, 'YYYY/MM/DD')
FROM stg_drivers d JOIN city c ON c.city_name = d.operating_city;

-- 3. junction: 'Dual-Platform (Both)' expands to one row per platform
INSERT INTO driver_platform (driver_id, platform_id, commission_pct)
SELECT d.driver_id, p.platform_id, d.platform_commission_pct::numeric
FROM stg_drivers d
JOIN platform p ON d.platform_affiliation = p.platform_name
                OR d.platform_affiliation = 'Dual-Platform (Both)';

-- 4. trips ('N/A' reason has no lookup row -> LEFT JOIN gives NULL)
INSERT INTO trip (trip_id, rider_id, driver_id, zone_id, ride_category_id,
                  request_timestamp, trip_status_id, cancellation_reason_id)
SELECT h.trip_id, h.rider_id, h.driver_id, h.zone_id, rc.ride_category_id,
       h.request_timestamp::timestamp, ts.trip_status_id, cr.cancellation_reason_id
FROM stg_trip_header h
JOIN ride_category rc ON rc.ride_category_name = h.ride_category
JOIN trip_status  ts ON ts.trip_status_name   = h.trip_status
LEFT JOIN cancellation_reason cr ON cr.cancellation_reason_name = h.cancellation_reason;

INSERT INTO trip_fare (trip_id, distance_km, duration_minutes, surge_multiplier,
                       base_fare_zar, tolls_zar, tip_zar, total_fare_zar,
                       platform_commission_zar, driver_payout_zar, payment_method_id)
SELECT f.trip_id, f.distance_km::numeric, f.duration_minutes::int,
       f.surge_multiplier::numeric, f.base_fare_zar::numeric, f.tolls_zar::numeric,
       f.tip_zar::numeric, f.total_fare_zar::numeric,
       f.platform_commission_zar::numeric, f.driver_payout_zar::numeric,
       pm.payment_method_id
FROM stg_trip_fare f
JOIN payment_method pm ON pm.payment_method_name = f.payment_method;