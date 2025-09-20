# Outputs for Ollama Deployment Module

output "namespace" {
  description = "Kubernetes namespace where Ollama is deployed"
  value       = kubernetes_namespace.ollama.metadata[0].name
}

output "service_name" {
  description = "Name of the Ollama service"
  value       = kubernetes_service.ollama.metadata[0].name
}

output "service_fqdn" {
  description = "Fully qualified domain name of the Ollama service"
  value       = "${kubernetes_service.ollama.metadata[0].name}.${kubernetes_namespace.ollama.metadata[0].name}.svc.cluster.local"
}

output "api_port" {
  description = "API port for Ollama service"
  value       = 11434
}

output "external_load_balancer_hostname" {
  description = "Hostname of the external LoadBalancer (if enabled)"
  value       = var.enable_external_access ? kubernetes_service.ollama.status[0].load_balancer[0].ingress[0].hostname : null
}

output "deployment_name" {
  description = "Name of the Ollama deployment"
  value       = kubernetes_deployment.ollama.metadata[0].name
}

output "storage_class_name" {
  description = "Name of the storage class used for Ollama volumes"
  value       = kubernetes_storage_class.ollama.metadata[0].name
}

output "pvc_name" {
  description = "Name of the PersistentVolumeClaim for model storage"
  value       = kubernetes_persistent_volume_claim.ollama_models.metadata[0].name
}

output "config_map_name" {
  description = "Name of the ConfigMap containing Ollama configuration"
  value       = kubernetes_config_map.ollama_config.metadata[0].name
}

output "service_account_name" {
  description = "Name of the service account used by Ollama pods"
  value       = kubernetes_service_account.ollama.metadata[0].name
}

output "headless_service_name" {
  description = "Name of the headless service (if clustering is enabled)"
  value       = var.enable_clustering ? kubernetes_service.ollama_headless[0].metadata[0].name : null
}

output "hpa_name" {
  description = "Name of the HorizontalPodAutoscaler (if enabled)"
  value       = var.enable_hpa ? kubernetes_horizontal_pod_autoscaler_v2.ollama[0].metadata[0].name : null
}

output "pdb_name" {
  description = "Name of the PodDisruptionBudget (if multiple replicas)"
  value       = var.replicas > 1 ? kubernetes_pod_disruption_budget_v1.ollama[0].metadata[0].name : null
}

output "connection_string" {
  description = "Connection string for Ollama API"
  value       = "http://${kubernetes_service.ollama.metadata[0].name}.${kubernetes_namespace.ollama.metadata[0].name}.svc.cluster.local:11434"
}

output "api_endpoint" {
  description = "API endpoint for Ollama service"
  value       = "${kubernetes_service.ollama.metadata[0].name}.${kubernetes_namespace.ollama.metadata[0].name}.svc.cluster.local:11434"
}

output "default_models" {
  description = "List of default models configured for download"
  value       = var.default_models
}

output "gpu_enabled" {
  description = "Whether GPU support is enabled"
  value       = var.enable_gpu
}

output "gpu_count" {
  description = "Number of GPUs allocated per pod"
  value       = var.enable_gpu ? var.gpu_count : 0
}

output "model_storage_size" {
  description = "Size of model storage"
  value       = var.model_storage_size
}

output "replicas" {
  description = "Number of Ollama replicas"
  value       = var.replicas
}