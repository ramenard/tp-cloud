variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "image_registry" {
  description = "Artifact Registry prefix (ex: europe-west1-docker.pkg.dev/PROJECT/tp-cloud)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

# ─── Auth service ──────────────────────────────────────────────────────────────
variable "jwt_secret" {
  description = "JWT signing secret"
  type        = string
  sensitive   = true
}

# ─── Database (Supabase) ───────────────────────────────────────────────────────
variable "db_host" {
  description = "Supabase DB host"
  type        = string
}

variable "db_port" {
  description = "Supabase DB port"
  type        = string
  default     = "5432"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "postgres"
}

variable "db_user" {
  description = "Database user"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# ─── AWS S3 ────────────────────────────────────────────────────────────────────
variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

# ─── Grafana Cloud ─────────────────────────────────────────────────────────────
variable "grafana_cloud_prom_url" {
  description = "Grafana Cloud Prometheus remote_write URL"
  type        = string
}

variable "grafana_cloud_user" {
  description = "Grafana Cloud Prometheus username"
  type        = string
}

variable "grafana_cloud_password" {
  description = "Grafana Cloud API key"
  type        = string
  sensitive   = true
}
