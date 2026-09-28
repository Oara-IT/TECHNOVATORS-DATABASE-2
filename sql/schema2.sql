DROP TABLE IF EXISTS drivers CASCADE;  -- old flat Phase 1 table
DROP TABLE IF EXISTS trip_fare, trip, driver_platform, driver, pricing_zone,
    rider, payment_method, cancellation_reason, trip_status, ride_category,
    platform, city CASCADE;

-- ---------- Lookup tables ----------
CREATE TABLE city (
    city_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_name  VARCHAR(60) NOT NULL UNIQUE
);
CREATE TABLE platform (
    platform_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    platform_name  VARCHAR(30) NOT NULL UNIQUE
);
CREATE TABLE ride_category (
    ride_category_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ride_category_name  VARCHAR(60) NOT NULL UNIQUE
);
CREATE TABLE trip_status (
    trip_status_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_status_name  VARCHAR(30) NOT NULL UNIQUE
);
CREATE TABLE cancellation_reason (
    cancellation_reason_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cancellation_reason_name  VARCHAR(40) NOT NULL UNIQUE
);
CREATE TABLE payment_method (
    payment_method_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_method_name  VARCHAR(30) NOT NULL UNIQUE
);

-- ---------- Core entities ----------
CREATE TABLE rider (
    rider_id VARCHAR(20) PRIMARY KEY
);

CREATE TABLE pricing_zone (
    zone_id           VARCHAR(40) PRIMARY KEY,
    zone_name         VARCHAR(100) NOT NULL UNIQUE,
    city_id           SMALLINT NOT NULL REFERENCES city(city_id),
    base_fare_zar     NUMERIC(8,2) NOT NULL CHECK (base_fare_zar >= 0),
    per_km_rate_zar   NUMERIC(6,2) NOT NULL CHECK (per_km_rate_zar >= 0),
    per_min_rate_zar  NUMERIC(6,2) NOT NULL CHECK (per_min_rate_zar >= 0)
);

CREATE TABLE driver (
    driver_id             VARCHAR(12) PRIMARY KEY,
    first_name            VARCHAR(60) NOT NULL,
    last_name             VARCHAR(60) NOT NULL,
    operating_city_id     SMALLINT NOT NULL REFERENCES city(city_id),
    driver_rating         NUMERIC(3,2) CHECK (driver_rating BETWEEN 0 AND 5),
    total_lifetime_trips  INTEGER NOT NULL DEFAULT 0 CHECK (total_lifetime_trips >= 0),
    onboarding_date       DATE NOT NULL
);

-- M:N  driver <-> platform (resolves "Dual-Platform (Both)")
CREATE TABLE driver_platform (
    driver_id       VARCHAR(12) NOT NULL REFERENCES driver(driver_id) ON DELETE CASCADE,
    platform_id     SMALLINT    NOT NULL REFERENCES platform(platform_id),
    commission_pct  NUMERIC(4,3) NOT NULL CHECK (commission_pct BETWEEN 0 AND 1),
    PRIMARY KEY (driver_id, platform_id)
);

-- ---------- Trips ----------
CREATE TABLE trip (
    trip_id                 VARCHAR(20) PRIMARY KEY,
    rider_id                VARCHAR(20) NOT NULL REFERENCES rider(rider_id),
    driver_id               VARCHAR(12) NOT NULL REFERENCES driver(driver_id),
    zone_id                 VARCHAR(40) NOT NULL REFERENCES pricing_zone(zone_id),
    ride_category_id        SMALLINT NOT NULL REFERENCES ride_category(ride_category_id),
    request_timestamp       TIMESTAMP NOT NULL,
    trip_status_id          SMALLINT NOT NULL REFERENCES trip_status(trip_status_id),
    cancellation_reason_id  SMALLINT REFERENCES cancellation_reason(cancellation_reason_id)  -- NULL when 'N/A'
);

-- 1:1 with trip (fare details of each trip)
CREATE TABLE trip_fare (
    trip_id                  VARCHAR(20) PRIMARY KEY REFERENCES trip(trip_id) ON DELETE CASCADE,
    distance_km              NUMERIC(7,2)  NOT NULL CHECK (distance_km >= 0),
    duration_minutes         INTEGER       NOT NULL CHECK (duration_minutes >= 0),
    surge_multiplier         NUMERIC(4,2)  NOT NULL CHECK (surge_multiplier > 0),
    base_fare_zar            NUMERIC(8,2)  NOT NULL CHECK (base_fare_zar >= 0),
    tolls_zar                NUMERIC(8,2)  NOT NULL DEFAULT 0 CHECK (tolls_zar >= 0),
    tip_zar                  NUMERIC(8,2)  NOT NULL DEFAULT 0 CHECK (tip_zar >= 0),
    total_fare_zar           NUMERIC(10,2) NOT NULL CHECK (total_fare_zar >= 0),
    platform_commission_zar  NUMERIC(10,2) NOT NULL CHECK (platform_commission_zar >= 0),
    driver_payout_zar        NUMERIC(10,2) NOT NULL CHECK (driver_payout_zar >= 0),
    payment_method_id        SMALLINT NOT NULL REFERENCES payment_method(payment_method_id),
    CONSTRAINT chk_fare_split
        CHECK (ABS(total_fare_zar - platform_commission_zar - driver_payout_zar) <= 0.02)
);