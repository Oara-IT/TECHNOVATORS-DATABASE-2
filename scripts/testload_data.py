"""
Create the normalized schema and load every raw CSV into Postgres.
Run from the repo root:  python scripts/load_postgres.py

Flow: schema.sql -> staging.sql -> COPY each CSV into a staging table
      -> transform.sql (INSERT ... SELECT into the 12 tables) -> validate.
"""
import csv
import os
import re
from pathlib import Path

import psycopg2
from dotenv import load_dotenv
from psycopg2 import sql

load_dotenv()  # connection settings come from .env

RAW_DIR = Path("Data/Raw")
SCHEMA_FILE = Path("sql/schema2.sql")
STAGING_FILE = Path("sql/staging.sql")
TRANSFORM_FILE = Path("sql/transform.sql")

# staging table -> CSV file (adjust the file names to yours)
STAGING = {
    "stg_zones": "pricing_surge_zones.csv",
    "stg_drivers": "sa_drivers.csv",
    "stg_trip_header": "trip_headers.csv",
    "stg_trip_fare": "trip_fare_breakdown.csv",
}

# final table -> staging table it must match row-for-row
FINAL_CHECKS = {
    "pricing_zone": "stg_zones",
    "driver": "stg_drivers",
    "trip": "stg_trip_header",
    "trip_fare": "stg_trip_fare",
}


def clean(name: str) -> str:
    """CSV header -> column name (lowercase, underscores). Must match staging.sql."""
    return re.sub(r"\W+", "_", name.strip().lower()).strip("_")


def count(cur, table: str) -> int:
    cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(table)))
    return cur.fetchone()[0]


def load_staging(cur, conn, table: str, csv_file: str) -> None:
    path = RAW_DIR / csv_file

    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = [clean(c) for c in next(reader)]
        expected = sum(1 for _ in reader)

    cols = sql.SQL(", ").join(sql.Identifier(c) for c in header)
    stmt = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv, HEADER true)").format(
        sql.Identifier(table), cols
    )
    with open(path, encoding="utf-8-sig", newline="") as f:
        cur.copy_expert(stmt.as_string(conn), f)

    loaded = count(cur, table)
    assert loaded == expected, f"{table}: CSV has {expected} rows, staged {loaded}"
    print(f"{table}: {loaded} rows staged")


def main() -> None:
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"),
        port=os.getenv("PG_PORT", "5432"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )
    # One transaction: if anything fails, nothing is left half-loaded
    with conn, conn.cursor() as cur:
        cur.execute(SCHEMA_FILE.read_text())    # (re)create the 12 tables
        cur.execute(STAGING_FILE.read_text())   # temp landing tables
        for table, csv_file in STAGING.items():
            load_staging(cur, conn, table, csv_file)

        cur.execute(TRANSFORM_FILE.read_text())  # split into normalized tables

        # Validate: nothing lost or dropped by the joins
        for final, stg in FINAL_CHECKS.items():
            n_final, n_stg = count(cur, final), count(cur, stg)
            assert n_final == n_stg, f"{final}: {n_final} loaded vs {n_stg} in CSV"
            print(f"{final}: {n_final}/{n_stg} rows loaded")
        cur.execute("SELECT count(DISTINCT driver_id) FROM driver_platform")
        assert cur.fetchone()[0] == count(cur, "driver"), \
            "some drivers have an unrecognised platform_affiliation"
        for t in ("city", "platform", "ride_category", "trip_status",
                  "cancellation_reason", "payment_method", "rider",
                  "driver_platform"):
            print(f"{t}: {count(cur, t)} rows")
    print("Load committed.")


if __name__ == "__main__":
    main()