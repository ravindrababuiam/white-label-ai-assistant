# Backup and Monitoring Resources for Qdrant

# ServiceAccount for backup operations
resource "kubernetes_service_account" "qdrant_backup" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-backup"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-backup"
      "app.kubernetes.io/component" = "backup"
      "customer"                    = var.customer_name
    })
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.qdrant_backup[0].arn
    }
  }
}

# IAM role for backup operations (IRSA)
resource "aws_iam_role" "qdrant_backup" {
  count = var.backup_enabled ? 1 : 0
  name  = "${var.customer_name}-qdrant-backup-role"

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
            "${replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${kubernetes_namespace.qdrant.metadata[0].name}:${var.customer_name}-qdrant-backup"
            "${replace(data.aws_eks_cluster.current.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.common_labels, {
    Name     = "${var.customer_name}-qdrant-backup-role"
    Purpose  = "Qdrant Backup Operations"
    Customer = var.customer_name
  })
}

resource "aws_iam_role_policy" "qdrant_backup" {
  count = var.backup_enabled ? 1 : 0
  name  = "${var.customer_name}-qdrant-backup-policy"
  role  = aws_iam_role.qdrant_backup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.backup_s3_bucket}",
          "arn:aws:s3:::${var.backup_s3_bucket}/*"
        ]
      }
    ]
  })
}

# Data sources for backup
data "aws_caller_identity" "current" {}
data "aws_eks_cluster" "current" {
  name = var.eks_cluster_name
}

# ConfigMap for backup script
resource "kubernetes_config_map" "qdrant_backup_script" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-backup-script"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-backup"
      "app.kubernetes.io/component" = "script"
      "customer"                    = var.customer_name
    })
  }

  data = {
    "backup.sh" = file("${path.module}/scripts/backup.sh")
  }
}

# CronJob for automated backups
resource "kubernetes_cron_job_v1" "qdrant_backup" {
  count = var.backup_enabled ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-backup"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-backup"
      "app.kubernetes.io/component" = "cronjob"
      "customer"                    = var.customer_name
    })
  }

  spec {
    schedule                      = var.backup_schedule
    timezone                     = "UTC"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit    = 3
    concurrency_policy           = "Forbid"

    job_template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "qdrant-backup"
          "app.kubernetes.io/component" = "job"
          "customer"                    = var.customer_name
        })
      }

      spec {
        backoff_limit = 3
        template {
          metadata {
            labels = merge(var.common_labels, {
              "app.kubernetes.io/name"      = "qdrant-backup"
              "app.kubernetes.io/component" = "pod"
              "customer"                    = var.customer_name
            })
          }

          spec {
            service_account_name = kubernetes_service_account.qdrant_backup[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name  = "backup"
              image = "amazon/aws-cli:2.13.25"

              command = ["/bin/bash", "/scripts/backup.sh"]

              env {
                name  = "AWS_DEFAULT_REGION"
                value = data.aws_region.current.id
              }

              env {
                name  = "CUSTOMER_NAME"
                value = var.customer_name
              }

              env {
                name  = "BACKUP_S3_BUCKET"
                value = var.backup_s3_bucket
              }

              env {
                name  = "QDRANT_SERVICE"
                value = "${kubernetes_service.qdrant.metadata[0].name}.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:6333"
              }

              dynamic "env" {
                for_each = var.enable_authentication ? [1] : []
                content {
                  name = "QDRANT_API_KEY"
                  value_from {
                    secret_key_ref {
                      name = kubernetes_secret.qdrant_auth[0].metadata[0].name
                      key  = "api-key"
                    }
                  }
                }
              }

              volume_mount {
                name       = "backup-script"
                mount_path = "/scripts"
                read_only  = true
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }

            volume {
              name = "backup-script"
              config_map {
                name         = kubernetes_config_map.qdrant_backup_script[0].metadata[0].name
                default_mode = "0755"
              }
            }
          }
        }
      }
    }
  }
}

# Data source for current region
data "aws_region" "current" {}

# Job for initial collection setup
resource "kubernetes_job_v1" "qdrant_init" {
  metadata {
    name      = "${var.customer_name}-qdrant-init"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant-init"
      "app.kubernetes.io/component" = "job"
      "customer"                    = var.customer_name
    })
  }

  spec {
    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name"      = "qdrant-init"
          "app.kubernetes.io/component" = "pod"
          "customer"                    = var.customer_name
        })
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "init-collections"
          image = "python:3.11-slim"

          command = ["python", "/scripts/init-collections.py"]

          env {
            name  = "QDRANT_HOST"
            value = "${kubernetes_service.qdrant.metadata[0].name}.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local"
          }

          env {
            name  = "QDRANT_PORT"
            value = "6333"
          }

          env {
            name  = "COLLECTIONS_CONFIG"
            value = jsonencode(var.collections_config)
          }

          dynamic "env" {
            for_each = var.enable_authentication ? [1] : []
            content {
              name = "QDRANT_API_KEY"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.qdrant_auth[0].metadata[0].name
                  key  = "api-key"
                }
              }
            }
          }

          volume_mount {
            name       = "init-script"
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

        init_container {
          name  = "install-deps"
          image = "python:3.11-slim"

          command = ["pip", "install", "requests"]

          volume_mount {
            name       = "pip-cache"
            mount_path = "/root/.cache/pip"
          }
        }

        volume {
          name = "init-script"
          config_map {
            name         = kubernetes_config_map.qdrant_config.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "pip-cache"
          empty_dir {}
        }
      }
    }

    backoff_limit = 5
  }

  depends_on = [kubernetes_stateful_set.qdrant]
}