# Kubernetes Services for Qdrant

# Service Account for Qdrant
resource "kubernetes_service_account" "qdrant" {
  metadata {
    name      = "${var.customer_name}-qdrant"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "service-account"
      "customer"                    = var.customer_name
    })
  }

  automount_service_account_token = false
}

# Headless service for StatefulSet
resource "kubernetes_service" "qdrant" {
  metadata {
    name      = "${var.customer_name}-qdrant"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }

  spec {
    cluster_ip = "None"
    
    selector = {
      "app.kubernetes.io/name" = "qdrant"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 6333
      target_port = 6333
      protocol    = "TCP"
    }

    port {
      name        = "grpc"
      port        = 6334
      target_port = 6334
      protocol    = "TCP"
    }

    port {
      name        = "p2p"
      port        = 6335
      target_port = 6335
      protocol    = "TCP"
    }
  }
}

# LoadBalancer service for external access (if enabled)
resource "kubernetes_service" "qdrant_external" {
  count = var.enable_external_access ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-external"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "external-service"
      "customer"                    = var.customer_name
    })
    annotations = merge(var.service_annotations, {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"                           = "internal"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
    })
  }

  spec {
    type = "LoadBalancer"
    
    selector = {
      "app.kubernetes.io/name" = "qdrant"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 6333
      target_port = 6333
      protocol    = "TCP"
    }

    port {
      name        = "grpc"
      port        = 6334
      target_port = 6334
      protocol    = "TCP"
    }

    load_balancer_source_ranges = var.allowed_cidr_blocks
  }
}

# Network Policy for Qdrant (if network policies are enabled)
resource "kubernetes_network_policy" "qdrant" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.customer_name}-qdrant-network-policy"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "qdrant"
      "app.kubernetes.io/component" = "network-policy"
      "customer"                    = var.customer_name
    })
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "qdrant"
        "customer"               = var.customer_name
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.qdrant.metadata[0].name
          }
        }
      }

      # Allow ingress from Open WebUI pods
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "open-webui"
          }
        }
      }

      # Allow ingress from monitoring
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6333"
      }

      ports {
        protocol = "TCP"
        port     = "6334"
      }
    }

    # Allow cluster communication for StatefulSet
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "qdrant"
            "customer"               = var.customer_name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6335"
      }
    }

    egress {
      # Allow DNS resolution
      to {}
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    egress {
      # Allow HTTPS for health checks and updates
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    # Allow cluster communication
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "qdrant"
            "customer"               = var.customer_name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6335"
      }
    }
  }
}