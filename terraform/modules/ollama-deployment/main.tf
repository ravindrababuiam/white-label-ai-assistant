# Ollama Deployment Module
# Provisions Ollama for local LLM inference with GPU support and model management

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Namespace for Ollama deployment
resource "kubernetes_namespace" "ollama" {
  metadata {
    name = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "llm-inference"
      "customer"                    = var.customer_name
    })
  }
}

# Storage class for Ollama model storage
resource "kubernetes_storage_class" "ollama" {
  metadata {
    name = "${var.customer_name}-ollama-storage"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "ollama-storage"
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

# ConfigMap for Ollama configuration and model management scripts
resource "kubernetes_config_map" "ollama_config" {
  metadata {
    name      = "${var.customer_name}-ollama-config"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "config"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "ollama.env" = templatefile("${path.module}/config/ollama.env", {
      log_level           = var.log_level
      max_loaded_models   = var.max_loaded_models
      num_parallel        = var.num_parallel
      max_queue          = var.max_queue
      gpu_memory_fraction = var.gpu_memory_fraction
      keep_alive         = var.keep_alive
    })

    "download-models.sh"    = file("${path.module}/scripts/download-models.sh")
    "health-check.sh"       = file("${path.module}/scripts/health-check.sh")
    "model-manager.py"      = file("${path.module}/scripts/model-manager.py")
    "cleanup-models.sh"     = file("${path.module}/scripts/cleanup-models.sh")
    
    "models.json" = jsonencode({
      default_models = var.default_models
      model_configs  = var.model_configs
    })
  }
}

# Service Account for Ollama
resource "kubernetes_service_account" "ollama" {
  metadata {
    name      = "${var.customer_name}-ollama"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "service-account"
      "customer"                    = var.customer_name
    })
  }

  automount_service_account_token = false
}

# PersistentVolumeClaim for model storage
resource "kubernetes_persistent_volume_claim" "ollama_models" {
  metadata {
    name      = "${var.customer_name}-ollama-models"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "storage"
      "customer"                    = var.customer_name
    })
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.ollama.metadata[0].name

    resources {
      requests = {
        storage = var.model_storage_size
      }
    }
  }
}

# Deployment for Ollama
resource "kubernetes_deployment" "ollama" {
  metadata {
    name      = "${var.customer_name}-ollama"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "server"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "ollama"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "ollama"
          "app.kubernetes.io/component" = "server"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "11434"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.ollama.metadata[0].name

        security_context {
          fs_group = 1000
        }

        # Init container for model downloads
        init_container {
          name  = "model-downloader"
          image = "${var.ollama_image}:${var.ollama_version}"

          command = ["/bin/bash", "/scripts/download-models.sh"]

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11434"
          }

          env {
            name  = "OLLAMA_MODELS"
            value = "/models"
          }

          env {
            name  = "OLLAMA_KEEP_ALIVE"
            value = "0"  # Don't keep models loaded during init
          }

          volume_mount {
            name       = "model-storage"
            mount_path = "/models"
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }
        }

        container {
          name  = "ollama"
          image = "${var.ollama_image}:${var.ollama_version}"

          port {
            name           = "http"
            container_port = 11434
            protocol       = "TCP"
          }

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11434"
          }

          env {
            name  = "OLLAMA_MODELS"
            value = "/models"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.ollama_config.metadata[0].name
            }
          }

          # GPU configuration (if enabled)
          dynamic "env" {
            for_each = var.enable_gpu ? [1] : []
            content {
              name  = "NVIDIA_VISIBLE_DEVICES"
              value = "all"
            }
          }

          dynamic "env" {
            for_each = var.enable_gpu ? [1] : []
            content {
              name  = "NVIDIA_DRIVER_CAPABILITIES"
              value = "compute,utility"
            }
          }

          volume_mount {
            name       = "model-storage"
            mount_path = "/models"
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = merge(
              {
                cpu    = var.resources.limits.cpu
                memory = var.resources.limits.memory
              },
              var.enable_gpu ? {
                "nvidia.com/gpu" = var.gpu_count
              } : {}
            )
          }

          liveness_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          startup_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 30  # Allow up to 5 minutes for startup
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

        # Sidecar container for model management
        container {
          name  = "model-manager"
          image = "python:3.11-slim"

          command = ["python", "/scripts/model-manager.py"]

          env {
            name  = "OLLAMA_HOST"
            value = "localhost:11434"
          }

          env {
            name  = "CHECK_INTERVAL"
            value = "300"  # 5 minutes
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
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

        volume {
          name = "model-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_models.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.ollama_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.ollama_config.metadata[0].name
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "10Gi"
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

        # GPU node affinity (if GPU is enabled)
        dynamic "affinity" {
          for_each = var.enable_gpu ? [1] : []
          content {
            node_affinity {
              required_during_scheduling_ignored_during_execution {
                node_selector_term {
                  match_expressions {
                    key      = "node.kubernetes.io/instance-type"
                    operator = "In"
                    values   = var.gpu_node_types
                  }
                }
              }
            }
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
                      values   = ["ollama"]
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