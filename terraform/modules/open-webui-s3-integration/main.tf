# Open WebUI S3 Integration Module
# Implements S3 document storage integration with security and metadata tracking

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ConfigMap for S3 integration configuration
resource "kubernetes_config_map" "s3_integration_config" {
  metadata {
    name      = "${var.customer_name}-s3-integration-config"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "s3-integration"
      "app.kubernetes.io/component" = "config"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "s3_config.json" = jsonencode({
      s3 = {
        bucket_name           = var.s3_bucket_name
        region               = var.s3_region
        endpoint             = var.s3_endpoint
        use_ssl              = var.s3_use_ssl
        path_style_access    = var.s3_path_style_access
        presigned_url_expiry = var.presigned_url_expiry
        max_file_size        = var.max_file_size
        allowed_extensions   = var.allowed_file_extensions
        virus_scan_enabled   = var.enable_virus_scanning
        metadata_indexing    = var.enable_metadata_indexing
      }
      
      upload = {
        chunk_size           = var.upload_chunk_size
        max_concurrent_uploads = var.max_concurrent_uploads
        retry_attempts       = var.upload_retry_attempts
        timeout_seconds      = var.upload_timeout_seconds
      }
      
      security = {
        content_type_validation = var.enable_content_type_validation
        filename_sanitization  = var.enable_filename_sanitization
        quarantine_suspicious  = var.quarantine_suspicious_files
        scan_timeout_seconds   = var.virus_scan_timeout
      }
      
      indexing = {
        extract_text         = var.extract_text_content
        generate_thumbnails  = var.generate_thumbnails
        extract_metadata     = var.extract_file_metadata
        ocr_enabled         = var.enable_ocr
      }
    })

    "document_processor.py" = file("${path.module}/scripts/document_processor.py")
    "s3_client.py"         = file("${path.module}/scripts/s3_client.py")
    "virus_scanner.py"     = file("${path.module}/scripts/virus_scanner.py")
    "metadata_extractor.py" = file("${path.module}/scripts/metadata_extractor.py")
    "upload_handler.py"    = file("${path.module}/scripts/upload_handler.py")
  }
}

# Secret for S3 integration credentials
resource "kubernetes_secret" "s3_integration_secrets" {
  metadata {
    name      = "${var.customer_name}-s3-integration-secrets"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "s3-integration"
      "app.kubernetes.io/component" = "secrets"
      "customer"                    = var.customer_name
    })
  }

  data = {
    aws_access_key_id     = var.aws_access_key_id
    aws_secret_access_key = var.aws_secret_access_key
    s3_encryption_key     = var.s3_encryption_key
    virus_scan_api_key    = var.virus_scan_api_key
  }

  type = "Opaque"
}

# ServiceAccount for S3 operations (IRSA)
resource "kubernetes_service_account" "s3_integration" {
  count = var.enable_irsa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-s3-integration"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "s3-integration"
      "app.kubernetes.io/component" = "service-account"
      "customer"                    = var.customer_name
    })
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_integration[0].arn
    }
  }

  automount_service_account_token = true
}

# IAM role for S3 operations (IRSA)
resource "aws_iam_role" "s3_integration" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.customer_name}-s3-integration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.customer_name}-s3-integration"
            "${replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_labels, {
    Name     = "${var.customer_name}-s3-integration-role"
    Purpose  = "S3 Document Storage Operations"
    Customer = var.customer_name
  })
}

# IAM policy for S3 operations
resource "aws_iam_role_policy" "s3_integration" {
  count = var.enable_irsa ? 1 : 0
  name  = "${var.customer_name}-s3-integration-policy"
  role  = aws_iam_role.s3_integration[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl",
          "s3:GetObjectAcl",
          "s3:PutObjectTagging",
          "s3:GetObjectTagging"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn != "" ? [var.kms_key_arn] : []
      }
    ]
  })
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "current" {
  count = var.enable_irsa ? 1 : 0
  name  = var.eks_cluster_name
}

# Deployment for document processing service
resource "kubernetes_deployment" "document_processor" {
  metadata {
    name      = "${var.customer_name}-document-processor"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-processor"
      "app.kubernetes.io/component" = "processor"
      "customer"                    = var.customer_name
    })
  }

  spec {
    replicas = var.processor_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "document-processor"
        "customer"               = var.customer_name
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "document-processor"
          "app.kubernetes.io/component" = "processor"
          "customer"                    = var.customer_name
        })
      }

      spec {
        service_account_name = var.enable_irsa ? kubernetes_service_account.s3_integration[0].metadata[0].name : "default"

        security_context {
          fs_group = 1000
        }

        container {
          name  = "document-processor"
          image = "${var.document_processor_image}:${var.document_processor_version}"

          port {
            name           = "http"
            container_port = 8000
            protocol       = "TCP"
          }

          # Environment variables
          env {
            name  = "S3_BUCKET_NAME"
            value = var.s3_bucket_name
          }

          env {
            name  = "S3_REGION"
            value = var.s3_region
          }

          env {
            name  = "S3_ENDPOINT"
            value = var.s3_endpoint
          }

          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3_integration_secrets.metadata[0].name
                key  = "aws_access_key_id"
              }
            }
          }

          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3_integration_secrets.metadata[0].name
                key  = "aws_secret_access_key"
              }
            }
          }

          env {
            name = "S3_ENCRYPTION_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3_integration_secrets.metadata[0].name
                key  = "s3_encryption_key"
              }
            }
          }

          env {
            name = "VIRUS_SCAN_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.s3_integration_secrets.metadata[0].name
                key  = "virus_scan_api_key"
              }
            }
          }

          env {
            name  = "ENABLE_VIRUS_SCANNING"
            value = tostring(var.enable_virus_scanning)
          }

          env {
            name  = "ENABLE_METADATA_INDEXING"
            value = tostring(var.enable_metadata_indexing)
          }

          env {
            name  = "MAX_FILE_SIZE"
            value = tostring(var.max_file_size)
          }

          env {
            name  = "QDRANT_URL"
            value = var.qdrant_url
          }

          env {
            name  = "QDRANT_API_KEY"
            value = var.qdrant_api_key
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
              cpu    = var.processor_resources.requests.cpu
              memory = var.processor_resources.requests.memory
            }
            limits = {
              cpu    = var.processor_resources.limits.cpu
              memory = var.processor_resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8000
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
            name = kubernetes_config_map.s3_integration_config.metadata[0].name
          }
        }

        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.s3_integration_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "temp"
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

# Service for document processor
resource "kubernetes_service" "document_processor" {
  metadata {
    name      = "${var.customer_name}-document-processor"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-processor"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "document-processor"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# HorizontalPodAutoscaler for document processor
resource "kubernetes_horizontal_pod_autoscaler_v2" "document_processor" {
  count = var.enable_processor_hpa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-document-processor-hpa"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-processor"
      "app.kubernetes.io/component" = "hpa"
      "customer"                    = var.customer_name
    })
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.document_processor.metadata[0].name
    }

    min_replicas = var.processor_hpa_min_replicas
    max_replicas = var.processor_hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.processor_hpa_cpu_target
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.processor_hpa_memory_target
        }
      }
    }
  }
}

# Network Policy for document processor
resource "kubernetes_network_policy" "document_processor" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.customer_name}-document-processor-network-policy"
    namespace = var.namespace
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "document-processor"
      "app.kubernetes.io/component" = "network-policy"
      "customer"                    = var.customer_name
    })
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "document-processor"
        "customer"               = var.customer_name
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
        port     = "8000"
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

    # Allow HTTPS for external services
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