# Outputs for Qdrant Deployment Module

output "namespace" {
  description = "Kubernetes namespace where Qdrant is deployed"
  value       = kubernetes_namespace.qdrant.metadata[0].name
}

output "service_name" {
  description = "Name of the Qdrant headless service"
  value       = kubernetes_service.qdrant.metadata[0].name
}

output "service_fqdn" {
  description = "Fully qualified domain name of the Qdrant service"
  value       = "${kubernetes_service.qdrant.metadata[0].name}.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local"
}

output "http_port" {
  description = "HTTP port for Qdrant API"
  value       = 6333
}

output "grpc_port" {
  description = "gRPC port for Qdrant API"
  value       = 6334
}

output "external_service_name" {
  description = "Name of the external LoadBalancer service (if enabled)"
  value       = var.enable_external_access ? kubernetes_service.qdrant_external[0].metadata[0].name : null
}

output "external_load_balancer_hostname" {
  description = "Hostname of the external LoadBalancer (if enabled)"
  value       = var.enable_external_access ? kubernetes_service.qdrant_external[0].status[0].load_balancer[0].ingress[0].hostname : null
}

output "statefulset_name" {
  description = "Name of the Qdrant StatefulSet"
  value       = kubernetes_stateful_set.qdrant.metadata[0].name
}

output "storage_class_name" {
  description = "Name of the storage class used for Qdrant volumes"
  value       = kubernetes_storage_class.qdrant.metadata[0].name
}

output "config_map_name" {
  description = "Name of the ConfigMap containing Qdrant configuration"
  value       = kubernetes_config_map.qdrant_config.metadata[0].name
}

output "service_account_name" {
  description = "Name of the service account used by Qdrant pods"
  value       = kubernetes_service_account.qdrant.metadata[0].name
}

output "secret_name" {
  description = "Name of the secret containing Qdrant API key (if authentication is enabled)"
  value       = var.enable_authentication ? kubernetes_secret.qdrant_auth[0].metadata[0].name : null
}

output "collections_config" {
  description = "Configuration of Qdrant collections"
  value       = var.collections_config
}

output "backup_job_name" {
  description = "Name of the backup CronJob (if backup is enabled)"
  value       = var.backup_enabled ? kubernetes_cron_job_v1.qdrant_backup[0].metadata[0].name : null
}

output "connection_string" {
  description = "Connection string for Qdrant HTTP API"
  value       = "http://${kubernetes_service.qdrant.metadata[0].name}.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:6333"
}

output "grpc_connection_string" {
  description = "Connection string for Qdrant gRPC API"
  value       = "${kubernetes_service.qdrant.metadata[0].name}.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:6334"
}