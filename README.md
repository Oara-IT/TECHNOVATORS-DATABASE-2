# TECHNOVATORS-DATABASE-2
# Technovators — Uber/Bolt Ride-Hailing Database Project (CMPG321)

## What this repo contains
- `Data/Raw/` — the 7 source CSVs
- `docker-compose.yml` — Postgres + pgAdmin, identical for everyone
- `sql/schema.sql` — typed table definitions (3NF)
- `scripts/` — Python scripts to load CSVs into Postgres, and (project owner only) push data to GCP
- `terraform/` — cloud infrastructure config (**project owner only**, do not run this)
- `dbt_uber/` — dbt project for building the star schema on BigQuery

## What you need from Oara before starting
Ask for these three things (sent privately, never through Git):
1. **GCP project ID** — currently `technovators`
2. **GCS bucket name** — currently `technovators-cmpg321-2026-raw`
3. **Confirmation you've been added to the GCP project** — you need a Google account added with `BigQuery Data Viewer` + `BigQuery Job User` + `BigQuery Data Editor` roles. Send Oara your Gmail address if you haven't already.


---

## Setup steps

### 1. Clone the repo
```bash
git clone https://github.com/Oara-IT/TECHNOVATORS-DATABASE-2.git
cd TECHNOVATORS-DATABASE-2
```
(Ask Oara to add you as a collaborator first if you get a permission error.)

### 2. Install prerequisites
- Docker Desktop (with WSL2 integration if on Windows)
- Python 3.10+
- `gcloud` CLI ([install guide](https://cloud.google.com/sdk/docs/install))

### 3. Set up your local environment file
```bash
cp .env.example .env
```
Open `.env` and fill in:
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` — pick any values, these are local-only and don't need to match anyone else's
- `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` — pick any values
- `GCP_PROJECT_ID` — from Oara (see above)
- `GCS_BUCKET` — from Oara (see above)
- `BQ_LOCATION` — from Oara (see above)

Leave `GOOGLE_APPLICATION_CREDENTIALS` **blank or delete the line** — you won't need it unless Oara asks you to run the extract/load scripts, which normally only she runs.

### 4. Start Postgres + pgAdmin
```bash
docker compose up -d
docker compose ps       # both should show "Up" / "healthy"
```

### 5. Create your Python virtual environment
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 6. Load the data into Postgres
```bash
python scripts/load_postgres.py
```
Should print row counts matching each CSV, with no errors.

### 7. Check it in pgAdmin
Open `http://localhost:5050`, log in with your `PGADMIN_EMAIL` / `PGADMIN_PASSWORD`, register a server:
- Host: `postgres` (not `localhost`)
- Port: `5432`
- Username / password / database: from your `.env`

You should now see the tables under `Databases → your db → Schemas → public → Tables`.

### 8. Set up dbt (for building the star schema)
```bash
pip install dbt-bigquery
cd dbt_uber
dbt init dbt_uber   # if not already scaffolded — check with your teammates first
```
When prompted for authentication method, choose **oauth** (not service_account) — this uses your own Google login, no key file needed:
```bash
gcloud auth application-default login --no-launch-browser
```
Follow the URL/code prompts. Then in `~/.dbt/profiles.yml`, set:
- `project`: from Oara
- `dataset`: `dbt_<your-name>` (your own dev dataset, don't reuse someone else's)
- `location`: from Oara

Test it:
```bash
dbt debug
dbt run
```

### 9. Do your work, then push
```bash
git add .
git commit -m "describe what you did"
git push
```
If your change touches `docker-compose.yml`, `terraform/`, or anything infrastructure-related, it needs Oara's review (CODEOWNERS) before merging.

---

## What you should NOT do
- Don't commit `.env` or any `.json` key file
- Don't run anything in `terraform/`
- Don't edit `Dockerfile` / `docker-compose.yml` without Communicating with Oara for review
- Don't write to the shared `raw` or `star` BigQuery datasets directly — build in your own `dbt_<name>` dataset first

## Who to ask
Anything GCP/infra-related (access, errors, credentials) → ask Oara before troubleshooting alone, since only he can see/fix the project-level config.