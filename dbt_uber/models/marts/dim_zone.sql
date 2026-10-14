select
    z.zone_id,
    z.zone_name,
    c.city_name,
    z.base_fare_zar,
    z.per_km_rate_zar,
    z.per_min_rate_zar,
    -- zone character per Phase 1 Table 3.4 — not in source data, documented manually
    case z.zone_name
        when 'ZONE_POTCH_NWU'        then 'University campus'
        when 'ZONE_VDBP_VAAL'        then 'Retail + campus'
        when 'ZONE_PTA_MENLYN'       then 'Commercial node'
        when 'ZONE_DBN_UMHLANGA'     then 'Coastal retail'
        when 'ZONE_PLZ_SUMMERSTRAND' then 'Coastal + airport'
        when 'ZONE_CPT_AIRPORT'      then 'Airport'
        when 'ZONE_CPT_WATERFRONT'   then 'Tourist waterfront'
        when 'ZONE_SANDTON'          then 'Financial core'
        when 'ZONE_JHB_CBD'          then 'Central business'
    end as zone_character,
    -- flags whether this city has >1 zone — needed for RQ2
    count(*) over (partition by c.city_name) > 1 as is_multi_zone_city
from {{ source('raw', 'pricing_zone') }} z
left join {{ source('raw', 'city') }} c on z.city_id = c.city_id