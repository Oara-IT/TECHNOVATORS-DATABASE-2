"""
Load Parquet files from GCS into the BigQuery raw_3NF dataset.
Run from repo root: python scripts/load_to_bigquery.py
"""

import json
import os
from datetime import datetime, timezone

from dotenv import load_dotenv
from google.cloud import bigquery
from google.oauth2 import service_account

load_dotenv()

TABLES = {
    "city": "city",
    "platform": "platform",
    "ride_category": "ride_category",
    "trip_status": "trip_status",
    "cancellation_reason": "cancellation_reason",
    "payment_method": "payment_method",
    "rider": "rider",
    "pricing_zone": "pricing_zone",
    "driver": "driver",
    "driver_platform": "driver_platform",
    "trip": "trip",
    "trip_fare": "trip_fare",
}


def get_bq_client():
    project_id = os.environ["GCP_PROJECT_ID"]
    key_json = os.environ.get("GCP_KEY")

    if key_json:
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(key_json)
        )
        return bigquery.Client(credentials=credentials, project=project_id)

    return bigquery.Client(project=project_id)


def main():
    project_id = os.environ["GCP_PROJECT_ID"]
    client = get_bq_client()
    bucket = os.environ["GCS_BUCKET"]

    # Kestra should pass this same value to the extraction script.
    run_date = os.getenv(
        "RUN_DATE",
        datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    )

    for table, folder in TABLES.items():
        print(f"Loading {table} to BigQuery...")

        uri = f"gs://{bucket}/3NF/{folder}/{table}.parquet"
        table_id = f"{project_id}.raw_3NF.{table}"

        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.PARQUET,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        )

        load_job = client.load_table_from_uri(
            uri,
            table_id,
            job_config=job_config,
        )
        load_job.result()

        loaded_table = client.get_table(table_id)
        print(f"{loaded_table.num_rows} rows loaded into {table_id}")

    print("BigQuery load completed successfully.")


if __name__ == "__main__":
    main()