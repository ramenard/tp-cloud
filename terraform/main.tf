locals {
  registry    = var.image_registry
  tag         = var.image_tag
  auth_image  = "${local.registry}/auth-service:${local.tag}"
  core_image  = "${local.registry}/core-service:${local.tag}"
  front_image = "${local.registry}/frontend:${local.tag}"
  alloy_image = "${local.registry}/monitoring:${local.tag}"
}

# ─── Auth Service ──────────────────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "auth" {
  name     = "auth-service"
  location = var.gcp_region

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.auth_image

      env {
        name  = "DB_HOST"
        value = var.db_host
      }
      env {
        name  = "DB_PORT"
        value = var.db_port
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASSWORD"
        value = var.db_password
      }
      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

resource "google_cloud_run_v2_service_iam_member" "auth_public" {
  name     = google_cloud_run_v2_service.auth.name
  location = var.gcp_region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─── Core Service ──────────────────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "core" {
  name     = "core-service"
  location = var.gcp_region

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.core_image

      env {
        name  = "DB_HOST"
        value = var.db_host
      }
      env {
        name  = "DB_PORT"
        value = var.db_port
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "DB_PASSWORD"
        value = var.db_password
      }
      env {
        name  = "AWS_ACCESS_KEY_ID"
        value = var.aws_access_key_id
      }
      env {
        name  = "AWS_SECRET_ACCESS_KEY"
        value = var.aws_secret_access_key
      }
      env {
        name  = "S3_BUCKET_NAME"
        value = var.s3_bucket_name
      }
      env {
        name  = "AWS_REGION"
        value = var.aws_region
      }
      env {
        name  = "AUTH_SERVICE_URL"
        value = google_cloud_run_v2_service.auth.uri
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

resource "google_cloud_run_v2_service_iam_member" "core_public" {
  name     = google_cloud_run_v2_service.core.name
  location = var.gcp_region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─── Frontend ──────────────────────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "frontend" {
  name     = "cloud-frontend"
  location = var.gcp_region

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = local.front_image

      env {
        name  = "AUTH_URL"
        value = google_cloud_run_v2_service.auth.uri
      }
      env {
        name  = "CORE_URL"
        value = google_cloud_run_v2_service.core.uri
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  name     = google_cloud_run_v2_service.frontend.name
  location = var.gcp_region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─── Monitoring (Grafana Alloy) ────────────────────────────────────────────────
resource "google_cloud_run_v2_service" "monitoring" {
  name     = "monitoring"
  location = var.gcp_region

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = local.alloy_image

      env {
        name  = "AUTH_SERVICE_HOST"
        value = trimprefix(google_cloud_run_v2_service.auth.uri, "https://")
      }
      env {
        name  = "CORE_SERVICE_HOST"
        value = trimprefix(google_cloud_run_v2_service.core.uri, "https://")
      }
      env {
        name  = "GRAFANA_CLOUD_PROM_URL"
        value = var.grafana_cloud_prom_url
      }
      env {
        name  = "GRAFANA_CLOUD_USER"
        value = var.grafana_cloud_user
      }
      env {
        name  = "GRAFANA_CLOUD_PASSWORD"
        value = var.grafana_cloud_password
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}

resource "google_cloud_run_v2_service_iam_member" "monitoring_public" {
  name     = google_cloud_run_v2_service.monitoring.name
  location = var.gcp_region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
