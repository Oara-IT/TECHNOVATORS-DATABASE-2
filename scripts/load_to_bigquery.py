"""
Load Parquet files from GCS into the BigQuery raw dataset.
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
    "drivers": "drivers",
    # "riders": "riders",
    # "trips": "trips",
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
    client = get_bq_client()
    bucket = os.environ["GCS_BUCKET"]

    # Kestra should pass this same value to the extraction script.
    run_date = os.getenv(
        "RUN_DATE",
        datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    )

    for table, folder in TABLES.items():
        print(f"Loading {table} to BigQuery...")

        uri = (
            f"gs://{bucket}/raw/{folder}/"
            f"extract_date={run_date}/{table}.parquet"
        )
        table_id = f"{os.environ['GCP_PROJECT_ID']}.raw.{table}"

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