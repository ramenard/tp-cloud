# ─── Étape 3 : Secret DB ───────────────────────────────────────────────────────
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }

  data = {
    username             = "postgres"
    password             = "MAUVAIS_MDP"
    dbname               = "postgres"
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    s3_bucket_name        = var.s3_bucket_name
  }
}

# ─── Backend ───────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "backend" {
  metadata {
    name = "cloud-backend"
    labels = { app = "cloud-backend" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "cloud-backend" }
    }

    template {
      metadata {
        labels = { app = "cloud-backend" }
      }

      spec {
        container {
          name  = "api"
          image = "cloud-back:latest"
          # Ne pas puller depuis Docker Hub, l'image est dans minikube
          image_pull_policy = "Never"

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

resource "kubernetes_service" "backend" {
  metadata {
    name = "cloud-backend-service"
  }

  spec {
    selector = { app = "cloud-backend" }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30081
    }

    type = "NodePort"
  }
}

# ─── Frontend ──────────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "frontend" {
  metadata {
    name = "cloud-frontend"
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