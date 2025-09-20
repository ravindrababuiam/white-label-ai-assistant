# Qdrant Vector Database Deployment Module
# Provisions Qdrant StatefulSet with persistent storage for document embeddings

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Namespace for Qdrant deployment
resource "kubernetes_namespace" "qdrant" {
  metadata {
    name = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "vector-database"
      "customer"                    = var.customer_name
    })
  }
}

# Storage class for Qdrant persistent volumes
resource "kubernetes_storage_class" "qdrant" {
  metadata {
    name = "${var.customer_name}-qdrant-storage"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant-storage"
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

# ConfigMap for Qdrant configuration
resource "kubernetes_config_map" "qdrant_config" {
  metadata {
    name      = "${var.customer_name}-qdrant-config"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "config"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "config.yaml" = yamlencode({
      log_level = var.log_level
      
      service = {
        host                = "0.0.0.0"
        http_port          = 6333
        grpc_port          = 6334
        enable_cors        = true
        max_request_size_mb = var.max_request_size_mb
      }

      storage = {
        storage_path       = "/qdrant/storage"
        snapshots_path     = "/qdrant/snapshots"
        on_disk_payload    = true
        wal_capacity_mb    = var.wal_capacity_mb
        wal_segments_ahead = 0
      }

      cluster = {
        enabled = var.cluster_enabled
        p2p = {
          port = 6335
        }
      }

      telemetry_disabled = var.telemetry_disabled
    })

    "init-collections.py" = file("${path.module}/scripts/init-collections.py")
  }
}

# Secret for Qdrant API key (if authentication is enabled)
resource "kubernetes_secret" "qdrant_auth" {
  count = var.enable_authentication ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-auth"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "auth"
      "customer"                    = var.customer_name
    })
  }

  data = {
    api-key = var.api_key
  }

  type = "Opaque"
}

# StatefulSet for Qdrant
resource "kubernetes_stateful_set" "qdrant" {
  metadata {
    name      = "${var.customer_name}-qdrant"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "database"
      "customer"                    = var.customer_name
    })
  }

  spec {
    service_name = kubernetes_service.qdrant.metadata[0].name
    replicas     = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "qdrant"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "qdrant"
          "app.kubernetes.io/component" = "database"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "6333"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.qdrant.metadata[0].name

        security_context {
          fs_group = 1000
        }

        init_container {
          name  = "init-permissions"
          image = "busybox:1.35"
          
          command = [
            "sh", "-c",
            "chown -R 1000:1000 /qdrant/storage /qdrant/snapshots && chmod -R 755 /qdrant/storage /qdrant/snapshots"
          ]

          volume_mount {
            name       = "qdrant-storage"
            mount_path = "/qdrant/storage"
          }

          volume_mount {
            name       = "qdrant-snapshots"
            mount_path = "/qdrant/snapshots"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name  = "qdrant"
          image = "${var.qdrant_image}:${var.qdrant_version}"

          port {
            name           = "http"
            container_port = 6333
            protocol       = "TCP"
          }

          port {
            name           = "grpc"
            container_port = 6334
            protocol       = "TCP"
          }

          port {
            name           = "p2p"
            container_port = 6335
            protocol       = "TCP"
          }

          env {
            name  = "QDRANT__SERVICE__HTTP_PORT"
            value = "6333"
          }

          env {
            name  = "QDRANT__SERVICE__GRPC_PORT"
            value = "6334"
          }

          dynamic "env" {
            for_each = var.enable_authentication ? [1] : []
            content {
              name = "QDRANT__SERVICE__API_KEY"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.qdrant_auth[0].metadata[0].name
                  key  = "api-key"
                }
              }
            }
          }

          volume_mount {
            name       = "qdrant-config"
            mount_path = "/qdrant/config"
            read_only  = true
          }

          volume_mount {
            name       = "qdrant-storage"
            mount_path = "/qdrant/storage"
          }

          volume_mount {
            name       = "qdrant-snapshots"
            mount_path = "/qdrant/snapshots"
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
              port = 6333
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 6333
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
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
          name = "qdrant-config"
          config_map {
            name = kubernetes_config_map.qdrant_config.metadata[0].name
          }
        }

        volume {
          name = "qdrant-snapshots"
          empty_dir {}
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

        dynamic "affinity" {
          for_each = var.enable_pod_anti_affinity ? [1] : []
          content {
            pod_anti_affinity {
              preferred_during_scheduling_ignored_during_execution {
                weight = 100
                pod_affinity_term {
                  label_selector {
                    match_expressions {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["qdrant"]
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

    volume_claim_template {
      metadata {
        name = "qdrant-storage"
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name" = "qdrant"
          "customer"               = var.customer_name
        })
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = kubernetes_storage_class.qdrant.metadata[0].name

        resources {
          requests = {
            storage = var.storage_size
          }
        }
      }
    }
  }
}