# Kubernetes Services and Networking for Open WebUI

# Service for Open WebUI
resource "kubernetes_service" "open_webui" {
  metadata {
    name      = "${var.customer_name}-open-webui"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "service"
      "customer"                    = var.customer_name
    })
    annotations = merge(var.service_annotations, {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    })
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "open-webui"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    type                        = var.enable_external_access ? "LoadBalancer" : "ClusterIP"
    load_balancer_source_ranges = var.enable_external_access ? var.allowed_cidr_blocks : null
  }
}

# External LoadBalancer service (if enabled)
resource "kubernetes_service" "open_webui_external" {
  count = var.enable_external_access ? 1 : 0

  metadata {
    name      = "${var.customer_name}-open-webui-external"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "external-service"
      "customer"                    = var.customer_name
    })
    annotations = merge(var.service_annotations, {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"                           = var.load_balancer_scheme
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"                         = var.ssl_certificate_arn
      "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"                        = "https"
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                 = "http"
    })
  }

  spec {
    type = "LoadBalancer"
    
    selector = {
      "app.kubernetes.io/name" = "open-webui"
      "customer"               = var.customer_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8080
      protocol    = "TCP"
    }

    load_balancer_source_ranges = var.allowed_cidr_blocks
  }
}

# Ingress for Open WebUI (if enabled)
resource "kubernetes_ingress_v1" "open_webui" {
  count = var.enable_ingress ? 1 : 0

  metadata {
    name      = "${var.customer_name}-open-webui-ingress"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "ingress"
      "customer"                    = var.customer_name
    })
    annotations = merge(var.ingress_annotations, {
      "kubernetes.io/ingress.class"                    = var.ingress_class
      "cert-manager.io/cluster-issuer"                = var.cert_manager_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"   = "100m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "300"
    })
  }

  spec {
    dynamic "tls" {
      for_each = var.ingress_tls_enabled ? [1] : []
      content {
        hosts       = [var.ingress_hostname]
        secret_name = "${var.customer_name}-open-webui-tls"
      }
    }

    rule {
      host = var.ingress_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.open_webui.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

# Network Policy for Open WebUI (if enabled)
resource "kubernetes_network_policy" "open_webui" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.customer_name}-open-webui-network-policy"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "network-policy"
      "customer"                    = var.customer_name
    })
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "open-webui"
        "customer"               = var.customer_name
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from ingress controller
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8080"
      }
    }

    # Allow ingress from same namespace
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.open_webui.metadata[0].name
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8080"
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
        port     = "8080"
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

    # Allow HTTP for internal service calls
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # Allow communication to Ollama
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "ollama"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "11434"
      }
    }

    # Allow communication to Qdrant
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "qdrant"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6333"
      }
    }

    # Allow communication to LiteLLM
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "4000"
      }
    }
  }
}

# HorizontalPodAutoscaler for Open WebUI (if enabled)
resource "kubernetes_horizontal_pod_autoscaler_v2" "open_webui" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = "${var.customer_name}-open-webui-hpa"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "hpa"
      "customer"                    = var.customer_name
    })
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.open_webui.metadata[0].name
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
resource "kubernetes_pod_disruption_budget_v1" "open_webui" {
  count = var.replicas > 1 ? 1 : 0

  metadata {
    name      = "${var.customer_name}-open-webui-pdb"
    namespace = kubernetes_namespace.open_webui.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "open-webui"
      "app.kubernetes.io/component" = "pdb"
      "customer"                    = var.customer_name
    })
  }

  spec {
    min_available = "50%"
    
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "open-webui"
        "customer"               = var.customer_name
      }
    }
  }
}