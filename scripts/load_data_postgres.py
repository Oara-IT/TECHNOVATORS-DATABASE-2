import os
import re
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

load_dotenv()
RAW = Path("Data/Raw")


def read(name):
    df = pd.read_csv(RAW / name, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    df.columns = [re.sub(r"\W+", "_", c.strip().lower()).strip("_") for c in df.columns]
    return df


def insert(cur, table, df):
    rows = [tuple(None if pd.isna(v) else (int(v) if isinstance(v, float) else v) for v in r)
            for r in df.itertuples(index=False, name=None)]
    execute_values(cur, f"INSERT INTO {table} ({', '.join(df.columns)}) VALUES %s", rows)
    print(f"{table}: {len(rows)} rows")


def lookup(cur, table, values):
    names = sorted({v for v in values if v != "N/A"})
    insert(cur, table, pd.DataFrame({f"{table}_name": names}))
    cur.execute(f"SELECT {table}_name, {table}_id FROM {table}")
    return dict(cur.fetchall())


zones, drivers = read("pricing_surge_zones.csv"), read("sa_drivers.csv")
header, fare = read("trip_headers.csv"), read("trip_fare_breakdown.csv")

conn = psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                        dbname=os.environ["POSTGRES_DB"], user=os.environ["POSTGRES_USER"],
                        password=os.environ["POSTGRES_PASSWORD"])
with conn, conn.cursor() as cur:
    cur.execute(Path("sql/schema2.sql").read_text())

    # lookup tables
    city = lookup(cur, "city", list(zones.city) + list(drivers.operating_city))
    platform = lookup(cur, "platform", ["Uber", "Bolt"])
    category = lookup(cur, "ride_category", header.ride_category)
    status = lookup(cur, "trip_status", header.trip_status)
    reason = lookup(cur, "cancellation_reason", header.cancellation_reason)
    payment = lookup(cur, "payment_method", fare.payment_method)

    # entities
    insert(cur, "rider", pd.DataFrame({"rider_id": sorted(header.rider_id.unique())}))
    insert(cur, "pricing_zone", zones.assign(city_id=zones.city.map(city))
           .drop(columns="city"))
    insert(cur, "driver", drivers.assign(operating_city_id=drivers.operating_city.map(city))
           [["driver_id", "first_name", "last_name", "operating_city_id",
             "driver_rating", "total_lifetime_trips", "onboarding_date"]])

    # driver <-> platform ("Dual-Platform (Both)" becomes two rows)
    dp = drivers[["driver_id", "platform_affiliation", "platform_commission_pct"]].copy()
    dp["platform_name"] = dp.platform_affiliation.apply(
        lambda a: ["Uber", "Bolt"] if a == "Dual-Platform (Both)" else [a])
    dp = dp.explode("platform_name")
    dp["platform_id"] = dp.platform_name.map(platform)
    insert(cur, "driver_platform", dp[["driver_id", "platform_id", "platform_commission_pct"]]
           .rename(columns={"platform_commission_pct": "commission_pct"}))

    # trips
    insert(cur, "trip", header.assign(
        ride_category_id=header.ride_category.map(category),
        trip_status_id=header.trip_status.map(status),
        cancellation_reason_id=header.cancellation_reason.map(reason),
    ).drop(columns=["ride_category", "trip_status", "cancellation_reason"]))
    insert(cur, "trip_fare", fare.assign(payment_method_id=fare.payment_method.map(payment))
           .drop(columns="payment_method"))

print("Data loaded.")