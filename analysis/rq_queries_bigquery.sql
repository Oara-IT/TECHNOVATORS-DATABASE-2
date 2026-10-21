-- =============================================================================
-- CMPG321 Group 30 (TECHNOVATORS Solutions): research-question queries
-- BigQuery Standard SQL. Run in the BigQuery console, project `technovators`.
-- Reads the dbt star schema (dbt_oara_star) and two raw_3NF lookup tables
-- (trip_status, ride_category). Results are discussed in the README and report.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Theme A: Spatial demand concentration
-- -----------------------------------------------------------------------------

-- RQ1: How is request volume distributed across the zones, and how concentrated is it?
SELECT
  z.zone_name,
  z.city_name,
  COUNT(*) AS requests,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
  RANK() OVER (ORDER BY COUNT(*) DESC) AS volume_rank,
  ROUND(100 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        / SUM(COUNT(*)) OVER (), 2) AS cumulative_pct
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.dbt_oara_star.dim_zone` AS z ON f.zone_id = z.zone_id
GROUP BY z.zone_name, z.city_name
ORDER BY requests DESC;

-- RQ2: Does city-level demand differ from zone-level demand, and does multi-zone coverage distort the ranking?
WITH zone_volume AS (
  SELECT z.city_name, z.zone_name, COUNT(*) AS requests
  FROM `technovators.dbt_oara_star.fact_trip` AS f
  JOIN `technovators.dbt_oara_star.dim_zone` AS z ON f.zone_id = z.zone_id
  GROUP BY z.city_name, z.zone_name
), city_volume AS (
  SELECT city_name,
         SUM(requests) AS requests,
         COUNT(*)      AS zones_covering
  FROM zone_volume
  GROUP BY city_name
)
SELECT
  city_name,
  zones_covering,
  requests,
  ROUND(requests / zones_covering, 0) AS requests_per_zone,
  RANK() OVER (ORDER BY requests DESC) AS rank_by_city_total,
  RANK() OVER (ORDER BY requests / zones_covering DESC) AS rank_per_zone
FROM city_volume
ORDER BY requests DESC;

-- RQ3: Which zones carry the highest request volume relative to the driver supply registered in their city?
WITH supply AS (
  SELECT operating_city AS city_name, COUNT(*) AS registered_drivers
  FROM `technovators.dbt_oara_star.dim_driver`
  GROUP BY operating_city
), demand AS (
  SELECT z.city_name, z.zone_name, COUNT(*) AS requests
  FROM `technovators.dbt_oara_star.fact_trip` AS f
  JOIN `technovators.dbt_oara_star.dim_zone` AS z ON f.zone_id = z.zone_id
  GROUP BY z.city_name, z.zone_name
)
SELECT
  d.zone_name,
  d.city_name,
  d.requests,
  s.registered_drivers,
  ROUND(d.requests / s.registered_drivers, 1) AS zone_req_per_driver,
  ROUND(SUM(d.requests) OVER (PARTITION BY d.city_name)
        / s.registered_drivers, 1) AS city_req_per_driver,
  RANK() OVER (ORDER BY d.requests / s.registered_drivers DESC) AS pressure_rank
FROM demand AS d
LEFT JOIN supply AS s ON d.city_name = s.city_name
ORDER BY pressure_rank;

-- -----------------------------------------------------------------------------
-- Theme B: Temporal rhythms
-- -----------------------------------------------------------------------------

-- RQ4: How does request volume vary across the 24-hour cycle, and are there identifiable commuter peaks?
SELECT
  request_hour,
  COUNT(*) AS requests,
  ROUND(AVG(COUNT(*)) OVER (), 1) AS hourly_mean,
  ROUND(100 * (COUNT(*) - AVG(COUNT(*)) OVER ())
        / AVG(COUNT(*)) OVER (), 2) AS pct_vs_mean
FROM `technovators.dbt_oara_star.fact_trip`
GROUP BY request_hour
ORDER BY request_hour;

-- RQ5: Does weekend-evening demand differ materially from weekday demand?
SELECT
  IF(d.is_weekend, 'Weekend', 'Weekday') AS day_type,
  CASE WHEN f.request_hour BETWEEN 18 AND 23 THEN 'Evening (18:00-23:59)'
       ELSE 'Rest of day' END AS period,
  COUNT(*) AS requests,
  COUNT(DISTINCT f.full_date) AS days,
  ROUND(COUNT(*) / COUNT(DISTINCT f.full_date), 1) AS avg_requests_per_day
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.dbt_oara_star.dim_date` AS d ON f.full_date = d.full_date
GROUP BY day_type, period
ORDER BY period, day_type;

-- RQ6: Do public holidays and month-end periods shift demand?
WITH daily AS (
  SELECT d.full_date, d.is_month_end,
         FORMAT_DATE('%Y-%m', d.full_date) AS year_month,
         COUNT(f.trip_id) AS requests          -- LEFT JOIN keeps days with no trips
  FROM `technovators.dbt_oara_star.dim_date` AS d
  LEFT JOIN `technovators.dbt_oara_star.fact_trip` AS f ON f.full_date = d.full_date
  GROUP BY d.full_date, d.is_month_end, year_month
)
SELECT
  year_month,
  ROUND(AVG(IF(is_month_end, requests, NULL)), 1)     AS month_end_avg,
  ROUND(AVG(IF(NOT is_month_end, requests, NULL)), 1) AS other_days_avg,
  ROUND(AVG(requests), 1)                             AS all_days_avg
FROM daily
GROUP BY year_month
HAVING COUNT(*) >= 28                                  -- complete months only
ORDER BY year_month;

-- -----------------------------------------------------------------------------
-- Theme C: Surge behaviour
-- -----------------------------------------------------------------------------

-- RQ7: What is the distribution of surge multipliers / surge categories, and how often is surge applied?
SELECT
  surge_band,
  surge_multiplier,
  COUNT(*) AS requests,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_requests,
  ROUND(100 * SUM(COUNT(*)) OVER (PARTITION BY surge_band)
        / SUM(COUNT(*)) OVER (), 2) AS band_pct
FROM `technovators.dbt_oara_star.fact_trip`
GROUP BY surge_band, surge_multiplier
ORDER BY surge_multiplier;

-- RQ8: Is surge applied in response to demand, or by a fixed temporal rule?
WITH hourly AS (
  SELECT request_hour,
         COUNT(*) AS requests,
         ROUND(AVG(surge_multiplier), 2) AS avg_surge,
         ROUND(100 * COUNTIF(is_surged) / COUNT(*), 1) AS pct_surged
  FROM `technovators.dbt_oara_star.fact_trip`
  GROUP BY request_hour
)
SELECT
  h.*,
  (SELECT ROUND(CORR(n, s), 4)              -- demand vs surge per zone-date-hour cell
   FROM (SELECT zone_id, full_date, request_hour,
                COUNT(*) AS n, AVG(surge_multiplier) AS s
         FROM `technovators.dbt_oara_star.fact_trip`
         GROUP BY zone_id, full_date, request_hour)) AS cell_corr_demand_surge
FROM hourly AS h
ORDER BY request_hour;

-- RQ9: Does surge vary across zones under equivalent demand conditions?
SELECT
  z.zone_name,
  ROUND(AVG(IF(f.request_hour BETWEEN 7 AND 9
            OR f.request_hour BETWEEN 16 AND 19, f.surge_multiplier, NULL)), 2) AS peak_avg_surge,
  ROUND(AVG(IF(f.request_hour BETWEEN 21 AND 23, f.surge_multiplier, NULL)), 2) AS late_avg_surge,
  ROUND(AVG(IF(f.request_hour < 7 OR f.request_hour BETWEEN 10 AND 15
            OR f.request_hour = 20, f.surge_multiplier, NULL)), 2)  AS offpeak_avg_surge,
  ROUND(AVG(f.surge_multiplier), 3) AS overall_avg_surge,
  COUNT(*) AS requests
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.dbt_oara_star.dim_zone` AS z ON f.zone_id = z.zone_id
GROUP BY z.zone_name
HAVING COUNT(*) > 1000
ORDER BY overall_avg_surge DESC;

-- -----------------------------------------------------------------------------
-- Theme D: Effectiveness and profit
-- -----------------------------------------------------------------------------

-- RQ10: How does completion rate vary across pricing bands?
SELECT
  f.surge_band,
  COUNT(*) AS requests,
  COUNTIF(ts.trip_status_name = 'COMPLETED')           AS completed,
  COUNTIF(ts.trip_status_name = 'CANCELLED_BY_RIDER')  AS rider_cancelled,
  COUNTIF(ts.trip_status_name = 'CANCELLED_BY_DRIVER') AS driver_cancelled,
  ROUND(100 * COUNTIF(ts.trip_status_name = 'COMPLETED') / COUNT(*), 1) AS completion_pct
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.raw_3NF.trip_status` AS ts ON f.trip_status_id = ts.trip_status_id
GROUP BY f.surge_band
ORDER BY MIN(f.surge_multiplier);

-- RQ11: What is the volume and estimated rand value of unfulfilled demand?
WITH zone_requests AS (
  SELECT zone_id, COUNT(*) AS requests
  FROM `technovators.dbt_oara_star.fact_trip`
  GROUP BY zone_id
)
SELECT
  z.zone_name,
  COUNT(*) AS unfulfilled,
  ROUND(100 * COUNT(*) / ANY_VALUE(r.requests), 1) AS unfulfilled_pct,
  ROUND(SUM(m.estimated_lost_fare_zar), 0) AS lost_fare_zar,
  ROUND(SUM(IF(m.surge_band != '1.0x (no surge)',
               m.estimated_lost_fare_zar, 0)), 0) AS lost_under_surge_zar
FROM `technovators.dbt_oara_star.mart_lost_revenue` AS m
JOIN `technovators.dbt_oara_star.dim_zone` AS z ON m.zone_id = z.zone_id
JOIN zone_requests AS r ON m.zone_id = r.zone_id
GROUP BY z.zone_name
ORDER BY lost_fare_zar DESC;

-- RQ12: Do riders abandon requests specifically because of pricing barriers?
SELECT
  f.surge_band,
  COUNTIF(f.is_cancelled) AS cancelled,
  COUNTIF(cr.cancellation_reason_name = 'PRICING_SURGE') AS price_cancels,
  ROUND(100 * COUNTIF(cr.cancellation_reason_name = 'PRICING_SURGE')
        / NULLIF(COUNTIF(f.is_cancelled), 0), 1) AS price_share_of_cancels_pct,
  ROUND(100 * COUNTIF(cr.cancellation_reason_name = 'PRICING_SURGE')
        / COUNT(*), 1) AS price_cancel_rate_pct
FROM `technovators.dbt_oara_star.fact_trip` AS f
LEFT JOIN `technovators.dbt_oara_star.dim_cancellation_reason` AS cr
       ON CAST(f.cancellation_reason_id AS INT64) = cr.cancellation_reason_id
GROUP BY f.surge_band
ORDER BY MIN(f.surge_multiplier);

-- RQ13: Is surge net profitable once abandoned requests are costed against revenue added?
WITH surge_gain AS (       -- commission that exists only because of the multiplier
  SELECT SUM(platform_commission_zar * (1 - 1 / surge_multiplier)) AS incremental
  FROM `technovators.dbt_oara_star.fact_trip`
  WHERE is_completed AND is_surged
), commission_rate AS (
  SELECT SUM(platform_commission_zar) / SUM(total_fare_zar) AS rate
  FROM `technovators.dbt_oara_star.fact_trip`
  WHERE is_completed
), surge_loss AS (       -- fares lost on surged requests cancelled for price
  SELECT SUM(estimated_lost_fare_zar) AS lost_fare
  FROM `technovators.dbt_oara_star.mart_lost_revenue`
  WHERE is_price_cancellation AND surge_band != '1.0x (no surge)'
)
SELECT
  ROUND(g.incremental, 0)                       AS incremental_commission_zar,
  ROUND(r.rate, 4)                              AS commission_rate,
  ROUND(l.lost_fare * r.rate, 0)                AS commission_forgone_zar,
  ROUND(g.incremental - l.lost_fare * r.rate, 0) AS net_surge_contribution_zar
FROM surge_gain AS g
CROSS JOIN commission_rate AS r
CROSS JOIN surge_loss AS l;

-- -----------------------------------------------------------------------------
-- Theme E: Under-serviced zones
-- -----------------------------------------------------------------------------

-- RQ14: Which zone-hour cells have the highest requests per active driver?
SELECT
  z.zone_name,
  h.request_hour,
  SUM(h.request_count) AS requests,
  SUM(h.active_driver_pool) AS active_driver_slots,
  ROUND(SUM(h.request_count) / SUM(h.active_driver_pool), 3) AS req_per_active_driver,
  ROUND(100 * AVG(h.unmet_rate), 1) AS avg_unmet_pct
FROM `technovators.dbt_oara_star.fact_zone_hour` AS h
JOIN `technovators.dbt_oara_star.dim_zone` AS z ON h.zone_id = z.zone_id
GROUP BY z.zone_name, h.request_hour
HAVING SUM(h.request_count) >= 150
ORDER BY req_per_active_driver DESC
LIMIT 10;

-- RQ15: Which cells rank highest on the composite Under-Service Index?
WITH cells AS (
  SELECT z.zone_name, h.request_hour,
         ROUND(AVG(h.under_service_index), 3) AS usi,
         ROUND(AVG(h.demand_pressure), 3) AS demand_pressure,
         ROUND(100 * AVG(h.unmet_rate), 1) AS unmet_pct
  FROM `technovators.dbt_oara_star.fact_zone_hour` AS h
  JOIN `technovators.dbt_oara_star.dim_zone` AS z ON h.zone_id = z.zone_id
  GROUP BY z.zone_name, h.request_hour
)
SELECT
  *,
  DENSE_RANK() OVER (ORDER BY usi DESC) AS usi_rank,
  MIN(usi) OVER () AS network_min_usi,
  MAX(usi) OVER () AS network_max_usi
FROM cells
QUALIFY usi_rank <= 10
ORDER BY usi_rank;

-- RQ16: Does ride-category mix or pricing differ in under-serviced zones?
WITH cell_usi AS (
  SELECT zone_id, request_hour, AVG(under_service_index) AS usi
  FROM `technovators.dbt_oara_star.fact_zone_hour`
  GROUP BY zone_id, request_hour
), ranked AS (
  SELECT zone_id, request_hour,
         IF(NTILE(4) OVER (ORDER BY usi DESC) = 1,
            'Most under-served 25%', 'Other 75%') AS cell_group
  FROM cell_usi
), mix AS (
  SELECT r.cell_group, rc.ride_category_name,
         COUNT(*) AS requests,
         COUNTIF(f.is_completed) AS completed,
         AVG(IF(f.is_completed, f.total_fare_zar, NULL)) AS avg_fare
  FROM `technovators.dbt_oara_star.fact_trip` AS f
  JOIN ranked AS r ON f.zone_id = r.zone_id AND f.request_hour = r.request_hour
  JOIN `technovators.raw_3NF.ride_category` AS rc ON f.ride_category_id = rc.ride_category_id
  GROUP BY r.cell_group, rc.ride_category_name
)
SELECT
  cell_group,
  ride_category_name,
  requests,
  ROUND(100 * requests / SUM(requests) OVER (PARTITION BY cell_group), 1) AS mix_pct,
  ROUND(100 * completed / requests, 1) AS completion_pct,
  ROUND(avg_fare, 0) AS avg_completed_fare_zar
FROM mix
ORDER BY cell_group, ride_category_name;

-- -----------------------------------------------------------------------------
-- Theme F: Cancellations and fulfilment
-- -----------------------------------------------------------------------------

-- RQ17: How does the cancellation burden divide across initiators and reasons?
SELECT
  cr.cancellation_reason_name,
  COUNTIF(ts.trip_status_name = 'CANCELLED_BY_RIDER')  AS by_rider,
  COUNTIF(ts.trip_status_name = 'CANCELLED_BY_DRIVER') AS by_driver,
  COUNT(*) AS total_cancelled,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_cancellations
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.raw_3NF.trip_status` AS ts ON f.trip_status_id = ts.trip_status_id
JOIN `technovators.dbt_oara_star.dim_cancellation_reason` AS cr
  ON CAST(f.cancellation_reason_id AS INT64) = cr.cancellation_reason_id
WHERE f.is_cancelled
GROUP BY cr.cancellation_reason_name
ORDER BY total_cancelled DESC;

-- RQ18: Do cancellation rates vary by zone and time of day?
SELECT
  z.zone_name,
  ROUND(100 * COUNTIF(f.is_cancelled AND f.request_hour BETWEEN 0 AND 5)
        / COUNTIF(f.request_hour BETWEEN 0 AND 5), 1)   AS night_pct,
  ROUND(100 * COUNTIF(f.is_cancelled AND f.request_hour BETWEEN 6 AND 11)
        / COUNTIF(f.request_hour BETWEEN 6 AND 11), 1)  AS morning_pct,
  ROUND(100 * COUNTIF(f.is_cancelled AND f.request_hour BETWEEN 12 AND 17)
        / COUNTIF(f.request_hour BETWEEN 12 AND 17), 1) AS afternoon_pct,
  ROUND(100 * COUNTIF(f.is_cancelled AND f.request_hour BETWEEN 18 AND 23)
        / COUNTIF(f.request_hour BETWEEN 18 AND 23), 1) AS evening_pct,
  ROUND(100 * COUNTIF(f.is_cancelled) / COUNT(*), 1)    AS overall_pct
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN `technovators.dbt_oara_star.dim_zone` AS z ON f.zone_id = z.zone_id
GROUP BY z.zone_name
ORDER BY overall_pct DESC;

-- RQ19: Do driver attributes explain fulfilment variation?
WITH drivers AS (
  SELECT driver_id, platform_affiliation,
         CASE WHEN driver_rating >= 4.8 THEN 'Excellent (4.8+)'
              WHEN driver_rating >= 4.5 THEN 'Good (4.5-4.79)'
              ELSE 'Average (<4.5)' END AS rating_tier
  FROM `technovators.dbt_oara_star.dim_driver`
)
SELECT 'Rating tier' AS attribute, d.rating_tier AS segment,
       COUNT(*) AS requests,
       ROUND(100 * COUNTIF(f.is_completed) / COUNT(*), 1) AS completion_pct,
       ROUND(100 * COUNTIF(f.trip_status_id = 1) / COUNT(*), 1) AS driver_cancel_pct
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN drivers AS d ON f.driver_id = d.driver_id
GROUP BY attribute, segment
UNION ALL
SELECT 'Platform', d.platform_affiliation,
       COUNT(*),
       ROUND(100 * COUNTIF(f.is_completed) / COUNT(*), 1),
       ROUND(100 * COUNTIF(f.trip_status_id = 1) / COUNT(*), 1)
FROM `technovators.dbt_oara_star.fact_trip` AS f
JOIN drivers AS d ON f.driver_id = d.driver_id
GROUP BY 1, 2
ORDER BY attribute, segment;
