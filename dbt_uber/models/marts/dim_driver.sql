select
    d.driver_id,
    d.first_name,
    d.last_name,
    c.city_name as operating_city,
    d.driver_rating,
    d.total_lifetime_trips,
    d.onboarding_date,
    -- collapse the M:N bridge into a readable label for RQ19
    string_agg(p.platform_name, ' + ' order by p.platform_name) as platform_affiliation,
    count(dp.platform_id) > 1 as is_dual_platform,
    avg(dp.commission_pct) as avg_commission_pct
from {{ source('raw', 'driver') }} d
left join {{ source('raw', 'city') }} c on d.operating_city_id = c.city_id
left join {{ source('raw', 'driver_platform') }} dp on d.driver_id = dp.driver_id
left join {{ source('raw', 'platform') }} p on dp.platform_id = p.platform_id
group by 1,2,3,4,5,6,7