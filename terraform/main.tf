terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Raw zone: read-only copy of the 3NF Postgres tables
resource "google_storage_bucket" "raw" {
  name                        = var.bucket_name
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
}

# BigQuery dataset for the raw 3NF copy
resource "google_bigquery_dataset" "raw" {
  dataset_id = "raw"
  project    = var.project_id
  location   = var.region
}

# BigQuery dataset for the star schema
resource "google_bigquery_dataset" "star" {
  dataset_id = "star"
  project    = var.project_id
  location   = var.region
}