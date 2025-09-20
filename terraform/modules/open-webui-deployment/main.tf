# Open WebUI Deployment Module
# Provisions Open WebUI with custom configuration for White Label AI Assistant

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Namespace for Open WebUI deployment
resource "kubernetes_namespace" "open_webui" {
  metadata {
    name = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "web-interface"
      "customer"                    = var.customer_name
    })
  }
}

# Storage class for Open WebUI persistent volumes
resource "kubernetes_storage_class" "open_webui" {
  metadata {
    name = "${var.customer_name}-open-webui-storage"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "open-webui-storage"
      "customer"               = var.customer_name
    })
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy        = "Retain"
  volume_binding_mode   = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = var.storage_type
    encrypted = "true"
    fsType    = "ext4"
  }
}

# ConfigMap for Open WebUI configuration
resource "kubernetes_config_map" "open_webui_config" {
  metadata {
    name      = "${var.customer_name}-open-webui-config"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "config"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "config.json" = jsonencode({
      ui = {
        title                = var.ui_title
        default_locale       = var.default_locale
        prompt_suggestions   = var.prompt_suggestions
        default_models       = var.default_models
        model_filter_enabled = var.model_filter_enabled
        model_filter_list    = var.model_filter_list
      }
      
      ollama = {
        base_urls = var.ollama_base_urls
        api_base_url = var.ollama_api_base_url
      }
      
      openai = {
        api_base_urls = var.openai_api_base_urls
        api_keys      = [] # Will be set via secrets
      }
      
      litellm = {
        api_base_url = var.litellm_api_base_url
        api_key      = "" # Will be set via secrets
      }
      
      features = {
        enable_signup         = var.enable_signup
        enable_login_form     = var.enable_login_form
        enable_web_search     = var.enable_web_search
        enable_image_generation = var.enable_image_generation
        enable_community_sharing = var.enable_community_sharing
        enable_message_rating = var.enable_message_rating
        enable_model_filter   = var.enable_model_filter
      }
      
      auth = {
        trusted_header_auth = var.trusted_header_auth
        webhook_url        = var.auth_webhook_url
      }
      
      rag = {
        enable_rag_hybrid_search = var.enable_rag_hybrid_search
        enable_rag_web_loader   = var.enable_rag_web_loader
        chunk_size              = var.rag_chunk_size
        chunk_overlap           = var.rag_chunk_overlap
        vector_db = {
          provider = "qdrant"
          config = {
            url = var.qdrant_url
            collection_name = var.qdrant_collection_name
          }
        }
      }
      
      storage = {
        s3 = {
          enabled    = var.enable_s3_storage
          bucket     = var.s3_bucket_name
          region     = var.s3_region
          endpoint   = var.s3_endpoint
        }
      }
    })

    "custom.css" = file("${path.module}/config/custom.css")
    "custom.js"  = file("${path.module}/config/custom.js")
    
    "init-db.py" = file("${path.module}/scripts/init-db.py")
    "backup-data.sh" = file("${path.module}/scripts/backup-data.sh")
    "health-check.py" = file("${path.module}/scripts/health-check.py")
  }
}

# Secret for Open WebUI sensitive configuration
resource "kubernetes_secret" "open_webui_secrets" {
  metadata {
    name      = "${var.customer_name}-open-webui-secrets"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "secrets"
      "customer"                    = var.customer_name
    })
  }

  data = {
    # JWT secret for session management
    jwt_secret = var.jwt_secret
    
    # Database connection
    database_url = var.database_url
    
    # API keys
    openai_api_key = var.openai_api_key
    litellm_api_key = var.litellm_api_key
    qdrant_api_key = var.qdrant_api_key
    
    # S3 credentials
    aws_access_key_id = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    
    # Webhook secrets
    webhook_secret = var.webhook_secret
  }

  type = "Opaque"
}

# Service Account for Open WebUI
resource "kubernetes_service_account" "open_webui" {
  metadata {
    name      = "${var.customer_name}-open-webui"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "service-account"
      "customer"                    = var.customer_name
    })
  }

  automount_service_account_token = false
}

# PersistentVolumeClaim for user data
resource "kubernetes_persistent_volume_claim" "open_webui_data" {
  metadata {
    name      = "${var.customer_name}-open-webui-data"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "storage"
      "customer"                    = var.customer_name
    })
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.open_webui.metadata[0].name

    resources {
      requests = {
        storage = var.data_storage_size
      }
    }
  }
}

# PersistentVolumeClaim for uploaded documents
resource "kubernetes_persistent_volume_claim" "open_webui_uploads" {
  metadata {
    name      = "${var.customer_name}-open-webui-uploads"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "uploads"
      "customer"                    = var.customer_name
    })
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.open_webui.metadata[0].name

    resources {
      requests = {
        storage = var.uploads_storage_size
      }
    }
  }
}

# Deployment for Open WebUI
resource "kubernetes_deployment" "open_webui" {
  metadata {
    name      = "${var.customer_name}-open-webui"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "web-server"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "open-webui"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "open-webui"
          "app.kubernetes.io/component" = "web-server"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.open_webui.metadata[0].name

        security_context {
          fs_group = 1000
        }

        # Init container for database initialization
        init_container {
          name  = "init-db"
          image = "python:3.11-slim"

          command = ["python", "/scripts/init-db.py"]

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "database_url"
              }
            }
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        container {
          name  = "open-webui"
          image = "${var.open_webui_image}:${var.open_webui_version}"

          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "WEBUI_NAME"
            value = var.ui_title
          }

          env {
            name  = "WEBUI_URL"
            value = var.webui_url
          }

          env {
            name  = "WEBUI_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "jwt_secret"
              }
            }
          }

          env {
            name  = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "database_url"
              }
            }
          }

          env {
            name  = "OLLAMA_BASE_URL"
            value = var.ollama_api_base_url
          }

          env {
            name  = "OPENAI_API_BASE_URL"
            value = var.litellm_api_base_url
          }

          env {
            name  = "OPENAI_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "litellm_api_key"
              }
            }
          }

          env {
            name  = "QDRANT_URL"
            value = var.qdrant_url
          }

          env {
            name  = "QDRANT_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "qdrant_api_key"
              }
            }
          }

          env {
            name  = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "aws_access_key_id"
              }
            }
          }

          env {
            name  = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "aws_secret_access_key"
              }
            }
          }

          env {
            name  = "S3_BUCKET_NAME"
            value = var.s3_bucket_name
          }

          env {
            name  = "S3_REGION"
            value = var.s3_region
          }

          # Feature flags
          env {
            name  = "ENABLE_SIGNUP"
            value = tostring(var.enable_signup)
          }

          env {
            name  = "ENABLE_LOGIN_FORM"
            value = tostring(var.enable_login_form)
          }

          env {
            name  = "ENABLE_WEB_SEARCH"
            value = tostring(var.enable_web_search)
          }

          env {
            name  = "ENABLE_RAG_HYBRID_SEARCH"
            value = tostring(var.enable_rag_hybrid_search)
          }

          env {
            name  = "RAG_CHUNK_SIZE"
            value = tostring(var.rag_chunk_size)
          }

          env {
            name  = "RAG_CHUNK_OVERLAP"
            value = tostring(var.rag_chunk_overlap)
          }

          # Volume mounts
          volume_mount {
            name       = "data"
            mount_path = "/app/backend/data"
          }

          volume_mount {
            name       = "uploads"
            mount_path = "/app/backend/uploads"
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/backend/config"
            read_only  = true
          }

          volume_mount {
            name       = "custom-assets"
            mount_path = "/app/build/static/custom"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 30
          }

          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            run_as_non_root           = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }
        }

        # Sidecar container for backup operations
        container {
          name  = "backup-sidecar"
          image = "alpine:3.18"

          command = ["/bin/sh", "-c", "while true; do sleep 3600; /scripts/backup-data.sh; done"]

          env {
            name  = "S3_BUCKET_NAME"
            value = var.s3_bucket_name
          }

          env {
            name  = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "aws_access_key_id"
              }
            }
          }

          env {
            name  = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.open_webui_secrets.metadata[0].name
                key  = "aws_secret_access_key"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/backend/data"
            read_only  = true
          }

          volume_mount {
            name       = "uploads"
            mount_path = "/app/backend/uploads"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            run_as_non_root           = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }
        }

        # Volumes
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.open_webui_data.metadata[0].name
          }
        }

        volume {
          name = "uploads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.open_webui_uploads.metadata[0].name
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.open_webui_config.metadata[0].name
          }
        }

        volume {
          name = "custom-assets"
          config_map {
            name = kubernetes_config_map.open_webui_config.metadata[0].name
            items {
              key  = "custom.css"
              path = "custom.css"
            }
            items {
              key  = "custom.js"
              path = "custom.js"
            }
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.open_webui_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "1Gi"
          }
        }

        node_selector = var.node_selector

        dynamic "toleration" {
          for_each = var.tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        # Pod anti-affinity for high availability
        dynamic "affinity" {
          for_each = var.enable_pod_anti_affinity && var.replicas > 1 ? [1] : []
          content {
            pod_anti_affinity {
              preferred_during_scheduling_ignored_during_execution {
                weight = 100
                pod_affinity_term {
                  label_selector {
                    match_expressions {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["open-webui"]
                    }
                  }
                  topology_key = "kubernetes.io/hostname"
                }
              }
            }
          }
        }
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "25%"
        max_surge       = "25%"
      }
    }
  }
}