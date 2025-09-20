# Open WebUI Qdrant Integration Module
# Implements vector search and embedding functionality for document retrieval

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# ConfigMap for Qdrant integration configuration
resource "kubernetes_config_map" "qdrant_integration_config" {
  metadata {
    name      = "${var.customer_name}-qdrant-integration-config"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-integration"
      "app.kubernetes.io/component" = "config"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "qdrant_config.json" = jsonencode({
      qdrant = {
        url                = var.qdrant_url
        collection_name    = var.collection_name
        vector_size        = var.vector_size
        distance_metric    = var.distance_metric
        timeout_seconds    = var.qdrant_timeout
        max_retries        = var.max_retries
        batch_size         = var.batch_size
        enable_compression = var.enable_compression
      }
      
      embeddings = {
        provider           = var.embedding_provider
        model_name         = var.embedding_model
        api_base_url       = var.embedding_api_url
        max_tokens         = var.max_embedding_tokens
        chunk_size         = var.text_chunk_size
        chunk_overlap      = var.text_chunk_overlap
        normalize_embeddings = var.normalize_embeddings
      }
      
      search = {
        default_limit      = var.default_search_limit
        max_limit          = var.max_search_limit
        score_threshold    = var.score_threshold
        enable_hybrid_search = var.enable_hybrid_search
        rerank_enabled     = var.enable_reranking
        rerank_top_k       = var.rerank_top_k
      }
      
      indexing = {
        auto_index_documents = var.auto_index_documents
        index_batch_size     = var.index_batch_size
        index_timeout        = var.index_timeout
        update_existing      = var.update_existing_documents
        extract_keywords     = var.extract_keywords
      }
      
      cache = {
        enable_embedding_cache = var.enable_embedding_cache
        cache_ttl_seconds     = var.cache_ttl_seconds
        max_cache_size        = var.max_cache_size
      }
    })

    "embedding_service.py"    = file("${path.module}/scripts/embedding_service.py")
    "vector_search.py"        = file("${path.module}/scripts/vector_search.py")
    "document_indexer.py"     = file("${path.module}/scripts/document_indexer.py")
    "qdrant_client.py"        = file("${path.module}/scripts/qdrant_client.py")
    "text_processor.py"       = file("${path.module}/scripts/text_processor.py")
    "search_api.py"           = file("${path.module}/scripts/search_api.py")
    "requirements.txt"        = file("${path.module}/scripts/requirements.txt")
  }
}

# Secret for Qdrant integration credentials
resource "kubernetes_secret" "qdrant_integration_secrets" {
  metadata {
    name      = "${var.customer_name}-qdrant-integration-secrets"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-integration"
      "app.kubernetes.io/component" = "secrets"
      "customer"                    = var.customer_name
    })
  }

  data = {
    qdrant_api_key      = var.qdrant_api_key
    embedding_api_key   = var.embedding_api_key
    openai_api_key      = var.openai_api_key
    huggingface_api_key = var.huggingface_api_key
  }

  type = "Opaque"
}

# Service Account for Qdrant operations
resource "kubernetes_service_account" "qdrant_integration" {
  metadata {
    name      = "${var.customer_name}-qdrant-integration"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-integration"
      "app.kubernetes.io/component" = "service-account"
      "customer"                    = var.customer_name
    })
  }

  automount_service_account_token = false
}

# Deployment for embedding service
resource "kubernetes_deployment" "embedding_service" {
  metadata {
    name      = "${var.customer_name}-embedding-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "embedding-service"
      "app.kubernetes.io/component" = "embeddings"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.embedding_service_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "embedding-service"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "embedding-service"
          "app.kubernetes.io/component" = "embeddings"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8001"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.qdrant_integration.metadata[0].name

        security_context {
          fs_group = 1000
        }

        container {
          name  = "embedding-service"
          image = "${var.embedding_service_image}:${var.embedding_service_version}"

          port {
            name           = "http"
            container_port = 8001
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "EMBEDDING_PROVIDER"
            value = var.embedding_provider
          }

          env {
            name  = "EMBEDDING_MODEL"
            value = var.embedding_model
          }

          env {
            name  = "EMBEDDING_API_URL"
            value = var.embedding_api_url
          }

          env {
            name = "EMBEDDING_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
                key  = "embedding_api_key"
              }
            }
          }

          env {
            name = "OPENAI_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
                key  = "openai_api_key"
              }
            }
          }

          env {
            name = "HUGGINGFACE_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
                key  = "huggingface_api_key"
              }
            }
          }

          env {
            name  = "VECTOR_SIZE"
            value = tostring(var.vector_size)
          }

          env {
            name  = "MAX_TOKENS"
            value = tostring(var.max_embedding_tokens)
          }

          env {
            name  = "NORMALIZE_EMBEDDINGS"
            value = tostring(var.normalize_embeddings)
          }

          env {
            name  = "ENABLE_CACHE"
            value = tostring(var.enable_embedding_cache)
          }

          env {
            name  = "CACHE_TTL"
            value = tostring(var.cache_ttl_seconds)
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/app/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "cache"
            mount_path = "/app/cache"
          }

          resources {
            requests = {
              cpu    = var.embedding_service_resources.requests.cpu
              memory = var.embedding_service_resources.requests.memory
            }
            limits = {
              cpu    = var.embedding_service_resources.limits.cpu
              memory = var.embedding_service_resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8001
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8001
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
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
          name = "config"
          config_map {
            name = kubernetes_config_map.qdrant_integration_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.qdrant_integration_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "cache"
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

# Deployment for vector search service
resource "kubernetes_deployment" "vector_search_service" {
  metadata {
    name      = "${var.customer_name}-vector-search-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "vector-search-service"
      "app.kubernetes.io/component" = "search"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.search_service_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "vector-search-service"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "vector-search-service"
          "app.kubernetes.io/component" = "search"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8002"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.qdrant_integration.metadata[0].name

        security_context {
          fs_group = 1000
        }

        container {
          name  = "vector-search-service"
          image = "${var.search_service_image}:${var.search_service_version}"

          port {
            name           = "http"
            container_port = 8002
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "QDRANT_URL"
            value = var.qdrant_url
          }

          env {
            name = "QDRANT_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
                key  = "qdrant_api_key"
              }
            }
          }

          env {
            name  = "COLLECTION_NAME"
            value = var.collection_name
          }

          env {
            name  = "EMBEDDING_SERVICE_URL"
            value = "http://${kubernetes_service.embedding_service.metadata[0].name}:8001"
          }

          env {
            name  = "DEFAULT_SEARCH_LIMIT"
            value = tostring(var.default_search_limit)
          }

          env {
            name  = "MAX_SEARCH_LIMIT"
            value = tostring(var.max_search_limit)
          }

          env {
            name  = "SCORE_THRESHOLD"
            value = tostring(var.score_threshold)
          }

          env {
            name  = "ENABLE_HYBRID_SEARCH"
            value = tostring(var.enable_hybrid_search)
          }

          env {
            name  = "ENABLE_RERANKING"
            value = tostring(var.enable_reranking)
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/app/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = var.search_service_resources.requests.cpu
              memory = var.search_service_resources.requests.memory
            }
            limits = {
              cpu    = var.search_service_resources.limits.cpu
              memory = var.search_service_resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8002
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8002
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
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
          name = "config"
          config_map {
            name = kubernetes_config_map.qdrant_integration_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.qdrant_integration_config.metadata[0].name
            default_mode = "0755"
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

# Service for embedding service
resource "kubernetes_service" "embedding_service" {
  metadata {
    name      = "${var.customer_name}-embedding-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "embedding-service"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "embedding-service"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8001
      target_port = 8001
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Service for vector search service
resource "kubernetes_service" "vector_search_service" {
  metadata {
    name      = "${var.customer_name}-vector-search-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "vector-search-service"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "vector-search-service"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8002
      target_port = 8002
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# HorizontalPodAutoscaler for embedding service
resource "kubernetes_horizontal_pod_autoscaler_v2" "embedding_service" {
  count = var.enable_embedding_hpa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-embedding-service-hpa"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "embedding-service"
      "app.kubernetes.io/component" = "hpa"
      "customer"                    = var.customer_name
    })
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.embedding_service.metadata[0].name
    }

    min_replicas = var.embedding_hpa_min_replicas
    max_replicas = var.embedding_hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.embedding_hpa_cpu_target
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.embedding_hpa_memory_target
        }
      }
    }
  }
}

# Deployment for document indexer service
resource "kubernetes_deployment" "document_indexer_service" {
  metadata {
    name      = "${var.customer_name}-document-indexer-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-indexer-service"
      "app.kubernetes.io/component" = "indexer"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.indexer_service_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "document-indexer-service"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "document-indexer-service"
          "app.kubernetes.io/component" = "indexer"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8003"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.qdrant_integration.metadata[0].name

        security_context {
          fs_group = 1000
        }

        container {
          name  = "document-indexer-service"
          image = "${var.indexer_service_image}:${var.indexer_service_version}"

          port {
            name           = "http"
            container_port = 8003
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "QDRANT_URL"
            value = var.qdrant_url
          }

          env {
            name = "QDRANT_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
                key  = "qdrant_api_key"
              }
            }
          }

          env {
            name  = "COLLECTION_NAME"
            value = var.collection_name
          }

          env {
            name  = "EMBEDDING_SERVICE_URL"
            value = "http://${kubernetes_service.embedding_service.metadata[0].name}:8001"
          }

          env {
            name  = "S3_ENDPOINT"
            value = var.s3_endpoint
          }

          env {
            name  = "S3_BUCKET"
            value = var.s3_bucket
          }

          env {
            name  = "AUTO_INDEX_DOCUMENTS"
            value = tostring(var.auto_index_documents)
          }

          env {
            name  = "INDEX_BATCH_SIZE"
            value = tostring(var.index_batch_size)
          }

          env {
            name  = "INDEX_TIMEOUT"
            value = tostring(var.index_timeout)
          }

          env {
            name  = "UPDATE_EXISTING_DOCUMENTS"
            value = tostring(var.update_existing_documents)
          }

          env {
            name  = "EXTRACT_KEYWORDS"
            value = tostring(var.extract_keywords)
          }

          env {
            name  = "TEXT_CHUNK_SIZE"
            value = tostring(var.text_chunk_size)
          }

          env {
            name  = "TEXT_CHUNK_OVERLAP"
            value = tostring(var.text_chunk_overlap)
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/app/scripts"
            read_only  = true
          }

          volume_mount {
            name       = "temp"
            mount_path = "/tmp"
          }

          resources {
            requests = {
              cpu    = var.indexer_service_resources.requests.cpu
              memory = var.indexer_service_resources.requests.memory
            }
            limits = {
              cpu    = var.indexer_service_resources.limits.cpu
              memory = var.indexer_service_resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8003
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8003
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
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
          name = "config"
          config_map {
            name = kubernetes_config_map.qdrant_integration_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.qdrant_integration_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "temp"
          empty_dir {
            size_limit = "2Gi"
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

# Deployment for search API service
resource "kubernetes_deployment" "search_api_service" {
  metadata {
    name      = "${var.customer_name}-search-api-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "search-api-service"
      "app.kubernetes.io/component" = "api"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.search_api_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "search-api-service"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "search-api-service"
          "app.kubernetes.io/component" = "api"
          "customer"                    = var.customer_name
        })
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8004"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.qdrant_integration.metadata[0].name

        security_context {
          fs_group = 1000
        }

        container {
          name  = "search-api-service"
          image = "${var.search_api_image}:${var.search_api_version}"

          port {
            name           = "http"
            container_port = 8004
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "VECTOR_SEARCH_SERVICE_URL"
            value = "http://${kubernetes_service.vector_search_service.metadata[0].name}:8002"
          }

          env {
            name  = "EMBEDDING_SERVICE_URL"
            value = "http://${kubernetes_service.embedding_service.metadata[0].name}:8001"
          }

          env {
            name  = "INDEXER_SERVICE_URL"
            value = "http://${kubernetes_service.document_indexer_service.metadata[0].name}:8003"
          }

          env {
            name  = "DEFAULT_SEARCH_LIMIT"
            value = tostring(var.default_search_limit)
          }

          env {
            name  = "MAX_SEARCH_LIMIT"
            value = tostring(var.max_search_limit)
          }

          env {
            name  = "DEFAULT_THRESHOLD"
            value = tostring(var.score_threshold)
          }

          env {
            name  = "CONTEXT_WINDOW"
            value = tostring(var.rag_context_window)
          }

          env {
            name  = "MAX_CONTEXT_CHUNKS"
            value = tostring(var.rag_max_chunks)
          }

          env {
            name  = "ENABLE_RAG"
            value = tostring(var.enable_rag)
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          volume_mount {
            name       = "scripts"
            mount_path = "/app/scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = var.search_api_resources.requests.cpu
              memory = var.search_api_resources.requests.memory
            }
            limits = {
              cpu    = var.search_api_resources.limits.cpu
              memory = var.search_api_resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8004
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8004
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
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
          name = "config"
          config_map {
            name = kubernetes_config_map.qdrant_integration_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.qdrant_integration_config.metadata[0].name
            default_mode = "0755"
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

# Service for document indexer service
resource "kubernetes_service" "document_indexer_service" {
  metadata {
    name      = "${var.customer_name}-document-indexer-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-indexer-service"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "document-indexer-service"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8003
      target_port = 8003
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Service for search API service
resource "kubernetes_service" "search_api_service" {
  metadata {
    name      = "${var.customer_name}-search-api-service"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "search-api-service"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "search-api-service"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8004
      target_port = 8004
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# HorizontalPodAutoscaler for search service
resource "kubernetes_horizontal_pod_autoscaler_v2" "vector_search_service" {
  count = var.enable_search_hpa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-vector-search-service-hpa"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "vector-search-service"
      "app.kubernetes.io/component" = "hpa"
      "customer"                    = var.customer_name
    })
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.vector_search_service.metadata[0].name
    }

    min_replicas = var.search_hpa_min_replicas
    max_replicas = var.search_hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.search_hpa_cpu_target
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.search_hpa_memory_target
        }
      }
    }
  }
}

# Network Policy for Qdrant integration services
resource "kubernetes_network_policy" "qdrant_integration" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-integration-network-policy"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-integration"
      "app.kubernetes.io/component" = "network-policy"
      "customer"                    = var.customer_name
    })
  }

  spec {
    pod_selector {
      match_labels = {
        "customer" = var.customer_name
      }
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values   = ["embedding-service", "vector-search-service", "document-indexer-service", "search-api-service"]
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from Open WebUI
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "open-webui"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8001"
      }

      ports {
        protocol = "TCP"
        port     = "8002"
      }

      ports {
        protocol = "TCP"
        port     = "8003"
      }

      ports {
        protocol = "TCP"
        port     = "8004"
      }
    }

    # Allow inter-service communication
    ingress {
      from {
        pod_selector {
          match_labels = {
            "customer" = var.customer_name
          }
          match_expressions {
            key      = "app.kubernetes.io/name"
            operator = "In"
            values   = ["embedding-service", "vector-search-service", "document-indexer-service", "search-api-service"]
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8001"
      }

      ports {
        protocol = "TCP"
        port     = "8002"
      }

      ports {
        protocol = "TCP"
        port     = "8003"
      }

      ports {
        protocol = "TCP"
        port     = "8004"
      }
    }

    # Allow DNS resolution
    egress {
      to {}
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow HTTPS for external API calls
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    # Allow communication to Qdrant
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "qdrant"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6333"
      }
    }
  }
}