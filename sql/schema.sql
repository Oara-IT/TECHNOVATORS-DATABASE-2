-- Typed table for drivers. Re-runnable: drops and recreates the table.
-- CASCADE also drops anything that references it (e.g. future foreign keys).
DROP TABLE IF EXISTS drivers CASCADE;

CREATE TABLE drivers (
    driver_id               VARCHAR(20)  PRIMARY KEY,          -- e.g. DRV_00001
    first_name              VARCHAR(50)  NOT NULL,
    last_name               VARCHAR(50)  NOT NULL,
    operating_city          VARCHAR(50)  NOT NULL,
    platform_affiliation    VARCHAR(30)  NOT NULL
        CHECK (platform_affiliation IN ('Uber', 'Bolt', 'Dual-Platform (Both)')),
    platform_commission_pct NUMERIC(3,2) NOT NULL
        CHECK (platform_commission_pct BETWEEN 0 AND 1),       -- 0.25 = 25%
    driver_rating           NUMERIC(3,2) NOT NULL
        CHECK (driver_rating BETWEEN 1 AND 5),
    total_lifetime_trips    INTEGER      NOT NULL
        CHECK (total_lifetime_trips >= 0),
    onboarding_date         DATE         NOT NULL              -- CSV format yyyy/mm/dd
);