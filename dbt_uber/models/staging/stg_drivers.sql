select
    driver_id,
    first_name,
    last_name,
    operating_city,
    platform_affiliation,
    platform_commission_pct,
    driver_rating,
    total_lifetime_trips,
    onboarding_date
from {{ source('raw', 'drivers') }}