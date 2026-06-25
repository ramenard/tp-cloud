locals {
  auth_image = var.image_registry != "" ? "${var.image_registry}/auth-service:${var.image_tag}" : "auth-service:latest"
  core_image = var.image_registry != "" ? "${var.image_registry}/core-service:${var.image_tag}" : "core-service:latest"
}

# ─── Secrets ───────────────────────────────────────────────────────────────────
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }

  data = {
    username             = "postgres"
    password             = "monpassword"
    dbname               = "postgres"
    aws_access_key_id    = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    s3_bucket_name       = var.s3_bucket_name
    jwt_secret           = var.jwt_secret
  }
}

# ─── Auth Service ──────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "auth" {
  metadata {
    name   = "auth-service"
    labels = { app = "auth-service" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "auth-service" }
    }

    template {
      metadata {
        labels = { app = "auth-service" }
      }

      spec {
        container {
          name              = "api"
          image             = local.auth_image
          image_pull_policy = var.image_registry != "" ? "Always" : "Never"

          port {
            container_port = 8080
          }

          env {
            name  = "DB_HOST"
            value = "my-postgres-postgresql"
          }
          env {
            name  = "DB_PORT"
            value = "5432"
          }
          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "dbname"
              }
            }
          }
          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "jwt_secret"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
            success_threshold     = 1
            timeout_seconds       = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "auth" {
  metadata {
    name = "auth-service"
  }

  spec {
    selector = { app = "auth-service" }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30082
    }

    type = "NodePort"
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "auth" {
  metadata {
    name = "auth-service-hpa"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.auth.metadata[0].name
    }

    min_replicas                      = 1
    max_replicas                      = 5
    target_cpu_utilization_percentage = 70
  }
}

# ─── Core Service ──────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "core" {
  metadata {
    name   = "core-service"
    labels = { app = "core-service" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "core-service" }
    }

    template {
      metadata {
        labels = { app = "core-service" }
      }

      spec {
        container {
          name              = "api"
          image             = local.core_image
          image_pull_policy = var.image_registry != "" ? "Always" : "Never"

          port {
            container_port = 8080
          }

          env {
            name  = "DB_HOST"
            value = "my-postgres-postgresql"
          }
          env {
            name  = "DB_PORT"
            value = "5432"
          }
          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "dbname"
              }
            }
          }
          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "aws_access_key_id"
              }
            }
          }
          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "aws_secret_access_key"
              }
            }
          }
          env {
            name = "S3_BUCKET_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.db_credentials.metadata[0].name
                key  = "s3_bucket_name"
              }
            }
          }
          env {
            name  = "AUTH_SERVICE_URL"
            value = "http://auth-service:8080"
          }

          readiness_probe {
            http_get {
              path = "/healthz/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
            success_threshold     = 1
            timeout_seconds       = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "core" {
  metadata {
    name = "core-service"
  }

  spec {
    selector = { app = "core-service" }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30081
    }

    type = "NodePort"
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "core" {
  metadata {
    name = "core-service-hpa"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.core.metadata[0].name
    }

    min_replicas                      = 1
    max_replicas                      = 5
    target_cpu_utilization_percentage = 70
  }
}

# ─── Frontend ──────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "frontend" {
  metadata {
    name   = "cloud-frontend"
    labels = { app = "cloud-frontend" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "cloud-frontend" }
    }

    template {
      metadata {
        labels = { app = "cloud-frontend" }
      }

      spec {
        container {
          name              = "nginx"
          image             = "cloud-front:latest"
          image_pull_policy = "Never"

          port {
            container_port = 8080
          }

          env {
            name  = "BACKEND_URL"
            value = "http://192.168.49.2:30081"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend" {
  metadata {
    name = "cloud-frontend-service"
  }

  spec {
    selector = { app = "cloud-frontend" }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30080
    }

    type = "NodePort"
  }
}
