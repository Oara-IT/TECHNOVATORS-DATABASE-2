variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for the bucket and BigQuery datasets"
  type        = string
  default     = "africa-south1"
}

variable "bucket_name" {
  description = "GCS bucket name for the raw data lake"
  type        = string
}