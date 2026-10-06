"""
Extract PostgreSQL tables and upload them to GCS as Parquet.
No business cleaning here — this is a source-shaped copy.
"""

import json
import os
import tempfile
from datetime import datetime, timezone

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from google.cloud import storage
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


def get_gcs_client():
    key_json = os.environ.get("GCP_KEY")

    if key_json:
        credentials = service_account.Credentials.from_service_account_info(
            json.loads(key_json)
        )
        return storage.Client(
            credentials=credentials,
            project=os.environ["GCP_PROJECT_ID"],
        )

    return storage.Client(project=os.environ["GCP_PROJECT_ID"])


def main():
    run_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    connection = psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"),
        port=os.getenv("PG_PORT", "5432"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )

    try:
        client = get_gcs_client()
        bucket = client.bucket(os.environ["GCS_BUCKET"])

        for table, folder in TABLES.items():
            print(f"Extracting {table}...")

            # Safe here because table names are controlled in TABLES above.
            dataframe = pd.read_sql(f'SELECT * FROM "{table}"', connection)

            with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as file:
                local_path = file.name

            try:
                dataframe.to_parquet(local_path, engine="pyarrow", index=False)

                blob_path = (
                   f"3NF/{folder}/{table}.parquet"
                )
                bucket.blob(blob_path).upload_from_filename(local_path)

                print(
                    f"{len(dataframe)} rows → "
                    f"gs://{os.environ['GCS_BUCKET']}/{blob_path}"
                )
            finally:
                if os.path.exists(local_path):
                    os.remove(local_path)

    finally:
        connection.close()

    print("Extract to GCS completed successfully.")


if __name__ == "__main__":
    main()