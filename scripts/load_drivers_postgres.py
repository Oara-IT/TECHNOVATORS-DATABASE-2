"""
Create the schema and load every raw CSV into Postgres.
Run from the repo root:  python scripts/load_postgres.py
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
SCHEMA_FILE = Path("sql/schema.sql")

# table name -> CSV file. Order matters: parent tables before the tables
# that reference them (foreign keys). Add one line per new table.
TABLES = {
    "drivers": "sa_drivers.csv",
    # "riders": "sa_riders.csv",
    # "vehicles": "vehicles.csv",
}


def clean(name: str) -> str:
    """CSV header -> column name (lowercase, underscores). Must match the DDL."""
    return re.sub(r"\W+", "_", name.strip().lower()).strip("_")


def load_table(cur, conn, table: str, csv_file: str) -> None:
    path = RAW_DIR / csv_file

    # Read the header (column order) and count data rows for validation
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = [clean(c) for c in next(reader)]
        expected = sum(1 for _ in reader)

    # Bulk-load with COPY, mapping CSV columns to table columns by name
    cols = sql.SQL(", ").join(sql.Identifier(c) for c in header)
    stmt = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv, HEADER true)").format(
        sql.Identifier(table), cols
    )
    with open(path, encoding="utf-8-sig", newline="") as f:
        cur.copy_expert(stmt.as_string(conn), f)

    # Validate that every CSV row arrived
    cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(table)))
    loaded = cur.fetchone()[0]
    assert loaded == expected, f"{table}: CSV has {expected} rows, loaded {loaded}"
    print(f"{table}: {loaded} rows loaded")


def main() -> None:
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"),
        port=os.getenv("PG_PORT", "5432"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )
    # One transaction: if any table fails, nothing is left half-loaded
    with conn, conn.cursor() as cur:
        cur.execute(SCHEMA_FILE.read_text())  # (re)create all tables
        for table, csv_file in TABLES.items():
            load_table(cur, conn, table, csv_file)


if __name__ == "__main__":
    main()