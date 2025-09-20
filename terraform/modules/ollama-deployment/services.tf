# Kubernetes Services for Ollama

# Service for Ollama API
resource "kubernetes_service" "ollama" {
  metadata {
    name      = "${var.customer_name}-ollama"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
    annotations = merge(var.service_annotations, {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "ollama"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 11434
      target_port = 11434
      protocol    = "TCP"
    }

    type = var.enable_external_access ? "LoadBalancer" : "ClusterIP"
    
    load_balancer_source_ranges = var.enable_external_access ? var.allowed_cidr_blocks : null
  }
}

# Headless service for StatefulSet-like behavior (if needed for clustering)
resource "kubernetes_service" "ollama_headless" {
  count = var.enable_clustering ? 1 : 0

  metadata {
    name      = "${var.customer_name}-ollama-headless"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "headless-service"
      "customer"                    = var.customer_name
    })
  }

  spec {
    cluster_ip = "None"
    
    selector = {
      "app.kubernetes.io/name" = "ollama"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 11434
      target_port = 11434
      protocol    = "TCP"
    }
  }
}

# Network Policy for Ollama (if enabled)
resource "kubernetes_network_policy" "ollama" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.customer_name}-ollama-network-policy"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "network-policy"
      "customer"                    = var.customer_name
    })
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "ollama"
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
        port     = "11434"
      }
    }

    # Allow ingress from same namespace (for clustering)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.ollama.metadata[0].name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "11434"
      }
    }

    # Allow ingress from monitoring
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "11434"
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

    # Allow HTTPS for model downloads
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    # Allow HTTP for model downloads (Ollama registry)
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # Allow communication within the same namespace
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.ollama.metadata[0].name
          }
        }
      }
    }
  }
}

# HorizontalPodAutoscaler for Ollama (if enabled)
resource "kubernetes_horizontal_pod_autoscaler_v2" "ollama" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-ollama-hpa"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "hpa"
      "customer"                    = var.customer_name
    })
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.ollama.metadata[0].name
    }

    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_cpu_target
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_memory_target
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 300
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 15
        }
      }

      scale_down {
        stabilization_window_seconds = 300
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
    }
  }
}

# PodDisruptionBudget for high availability
resource "kubernetes_pod_disruption_budget_v1" "ollama" {
  count = var.replicas > 1 ? 1 : 0

  metadata {
    name      = "${var.customer_name}-ollama-pdb"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "ollama"
      "app.kubernetes.io/component" = "pdb"
      "customer"                    = var.customer_name
    })
  }

  spec {
    min_available = "50%"
    
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "ollama"
        "customer"               = var.customer_name
      }
    }
  }
}