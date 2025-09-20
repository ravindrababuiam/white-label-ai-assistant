# Outputs for Open WebUI Deployment Module

output "namespace" {
  description = "Kubernetes namespace where Open WebUI is deployed"
  value       = kubernetes_namespace.open_webui.metadata[0].name
}

output "service_name" {
  description = "Name of the Open WebUI service"
  value       = kubernetes_service.open_webui.metadata[0].name
}

output "service_fqdn" {
  description = "Fully qualified domain name of the Open WebUI service"
  value       = "${kubernetes_service.open_webui.metadata[0].name}.${kubernetes_namespace.open_webui.metadata[0].name}.svc.cluster.local"
}

output "http_port" {
  description = "HTTP port for Open WebUI service"
  value       = 8080
}

output "external_load_balancer_hostname" {
  description = "Hostname of the external LoadBalancer (if enabled)"
  value       = var.enable_external_access ? kubernetes_service.open_webui_external[0].status[0].load_balancer[0].ingress[0].hostname : null
}

output "deployment_name" {
  description = "Name of the Open WebUI deployment"
  value       = kubernetes_deployment.open_webui.metadata[0].name
}

output "storage_class_name" {
  description = "Name of the storage class used for Open WebUI volumes"
  value       = kubernetes_storage_class.open_webui.metadata[0].name
}

output "data_pvc_name" {
  description = "Name of the PersistentVolumeClaim for user data"
  value       = kubernetes_persistent_volume_claim.open_webui_data.metadata[0].name
}

output "uploads_pvc_name" {
  description = "Name of the PersistentVolumeClaim for uploads"
  value       = kubernetes_persistent_volume_claim.open_webui_uploads.metadata[0].name
}

output "config_map_name" {
  description = "Name of the ConfigMap containing Open WebUI configuration"
  value       = kubernetes_config_map.open_webui_config.metadata[0].name
}

output "secret_name" {
  description = "Name of the secret containing Open WebUI sensitive configuration"
  value       = kubernetes_secret.open_webui_secrets.metadata[0].name
}

output "service_account_name" {
  description = "Name of the service account used by Open WebUI pods"
  value       = kubernetes_service_account.open_webui.metadata[0].name
}

output "ingress_name" {
  description = "Name of the ingress (if enabled)"
  value       = var.enable_ingress ? kubernetes_ingress_v1.open_webui[0].metadata[0].name : null
}

output "hpa_name" {
  description = "Name of the HorizontalPodAutoscaler (if enabled)"
  value       = var.enable_hpa ? kubernetes_horizontal_pod_autoscaler_v2.open_webui[0].metadata[0].name : null
}

output "pdb_name" {
  description = "Name of the PodDisruptionBudget (if multiple replicas)"
  value       = var.replicas > 1 ? kubernetes_pod_disruption_budget_v1.open_webui[0].metadata[0].name : null
}

output "connection_string" {
  description = "Connection string for Open WebUI HTTP interface"
  value       = "http://${kubernetes_service.open_webui.metadata[0].name}.${kubernetes_namespace.open_webui.metadata[0].name}.svc.cluster.local:8080"
}

output "ui_title" {
  description = "Title configured for the Open WebUI interface"
  value       = var.ui_title
}

output "replicas" {
  description = "Number of Open WebUI replicas"
  value       = var.replicas
}

output "data_storage_size" {
  description = "Size of user data storage"
  value       = var.data_storage_size
}

output "uploads_storage_size" {
  description = "Size of uploads storage"
  value       = var.uploads_storage_size
}

output "ollama_integration_enabled" {
  description = "Whether Ollama integration is configured"
  value       = var.ollama_api_base_url != ""
}

output "litellm_integration_enabled" {
  description = "Whether LiteLLM integration is configured"
  value       = var.litellm_api_base_url != ""
}

output "qdrant_integration_enabled" {
  description = "Whether Qdrant integration is configured"
  value       = var.qdrant_url != ""
}

output "s3_integration_enabled" {
  description = "Whether S3 integration is enabled"
  value       = var.enable_s3_storage
}

output "rag_enabled" {
  description = "Whether RAG functionality is enabled"
  value       = var.enable_rag_hybrid_search
}

output "backup_enabled" {
  description = "Whether automated backups are enabled"
  value       = var.backup_enabled
}