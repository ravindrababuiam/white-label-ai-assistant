# Outputs for Open WebUI Qdrant Integration Module

output "embedding_service_name" {
  description = "Name of the embedding service"
  value       = kubernetes_service.embedding_service.metadata[0].name
}

output "embedding_service_fqdn" {
  description = "Fully qualified domain name of the embedding service"
  value       = "${kubernetes_service.embedding_service.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "embedding_service_endpoint" {
  description = "Embedding service API endpoint"
  value       = "http://${kubernetes_service.embedding_service.metadata[0].name}.${var.namespace}.svc.cluster.local:8001"
}

output "search_service_name" {
  description = "Name of the vector search service"
  value       = kubernetes_service.vector_search_service.metadata[0].name
}

output "search_service_fqdn" {
  description = "Fully qualified domain name of the vector search service"
  value       = "${kubernetes_service.vector_search_service.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "search_service_endpoint" {
  description = "Vector search service API endpoint"
  value       = "http://${kubernetes_service.vector_search_service.metadata[0].name}.${var.namespace}.svc.cluster.local:8002"
}

output "qdrant_url" {
  description = "Qdrant server URL"
  value       = var.qdrant_url
}

output "collection_name" {
  description = "Qdrant collection name for document embeddings"
  value       = var.collection_name
}

output "vector_size" {
  description = "Size of embedding vectors"
  value       = var.vector_size
}

output "embedding_provider" {
  description = "Embedding provider being used"
  value       = var.embedding_provider
}

output "embedding_model" {
  description = "Embedding model being used"
  value       = var.embedding_model
}

output "config_map_name" {
  description = "Name of the ConfigMap containing Qdrant integration configuration"
  value       = kubernetes_config_map.qdrant_integration_config.metadata[0].name
}

output "secret_name" {
  description = "Name of the secret containing Qdrant integration credentials"
  value       = kubernetes_secret.qdrant_integration_secrets.metadata[0].name
}

output "service_account_name" {
  description = "Name of the service account for Qdrant operations"
  value       = kubernetes_service_account.qdrant_integration.metadata[0].name
}

output "embedding_deployment_name" {
  description = "Name of the embedding service deployment"
  value       = kubernetes_deployment.embedding_service.metadata[0].name
}

output "search_deployment_name" {
  description = "Name of the search service deployment"
  value       = kubernetes_deployment.vector_search_service.metadata[0].name
}

output "embedding_hpa_name" {
  description = "Name of the embedding service HPA (if enabled)"
  value       = var.enable_embedding_hpa ? kubernetes_horizontal_pod_autoscaler_v2.embedding_service[0].metadata[0].name : null
}

output "search_hpa_name" {
  description = "Name of the search service HPA (if enabled)"
  value       = var.enable_search_hpa ? kubernetes_horizontal_pod_autoscaler_v2.vector_search_service[0].metadata[0].name : null
}

output "embedding_service_replicas" {
  description = "Number of embedding service replicas"
  value       = var.embedding_service_replicas
}

output "search_service_replicas" {
  description = "Number of search service replicas"
  value       = var.search_service_replicas
}

output "hybrid_search_enabled" {
  description = "Whether hybrid search is enabled"
  value       = var.enable_hybrid_search
}

output "reranking_enabled" {
  description = "Whether result reranking is enabled"
  value       = var.enable_reranking
}

output "auto_indexing_enabled" {
  description = "Whether automatic document indexing is enabled"
  value       = var.auto_index_documents
}

output "embedding_cache_enabled" {
  description = "Whether embedding caching is enabled"
  value       = var.enable_embedding_cache
}

output "text_chunk_size" {
  description = "Size of text chunks for embedding"
  value       = var.text_chunk_size
}

output "text_chunk_overlap" {
  description = "Overlap between text chunks"
  value       = var.text_chunk_overlap
}

output "default_search_limit" {
  description = "Default number of search results"
  value       = var.default_search_limit
}

output "score_threshold" {
  description = "Minimum similarity score threshold"
  value       = var.score_threshold
}

# Additional Service Outputs
output "indexer_service_name" {
  description = "Name of the document indexer service"
  value       = kubernetes_service.document_indexer_service.metadata[0].name
}

output "indexer_service_endpoint" {
  description = "Document indexer service API endpoint"
  value       = "http://${kubernetes_service.document_indexer_service.metadata[0].name}.${var.namespace}.svc.cluster.local:8003"
}

output "search_api_service_name" {
  description = "Name of the search API service"
  value       = kubernetes_service.search_api_service.metadata[0].name
}

output "search_api_endpoint" {
  description = "Search API service endpoint"
  value       = "http://${kubernetes_service.search_api_service.metadata[0].name}.${var.namespace}.svc.cluster.local:8004"
}

output "indexer_deployment_name" {
  description = "Name of the document indexer deployment"
  value       = kubernetes_deployment.document_indexer_service.metadata[0].name
}

output "search_api_deployment_name" {
  description = "Name of the search API deployment"
  value       = kubernetes_deployment.search_api_service.metadata[0].name
}

output "rag_enabled" {
  description = "Whether RAG functionality is enabled"
  value       = var.enable_rag
}

output "s3_configuration" {
  description = "S3 configuration for document storage"
  value = {
    endpoint = var.s3_endpoint
    bucket   = var.s3_bucket
  }
}

output "integration_status" {
  description = "Qdrant integration configuration status"
  value = {
    qdrant_configured         = var.qdrant_url != ""
    embedding_provider        = var.embedding_provider
    vector_size              = var.vector_size
    collection_name          = var.collection_name
    hybrid_search_enabled    = var.enable_hybrid_search
    auto_indexing_enabled    = var.auto_index_documents
    embedding_cache_enabled  = var.enable_embedding_cache
    reranking_enabled        = var.enable_reranking
    embedding_hpa_enabled    = var.enable_embedding_hpa
    search_hpa_enabled       = var.enable_search_hpa
    rag_enabled              = var.enable_rag
    indexer_service_replicas = var.indexer_service_replicas
    search_api_replicas      = var.search_api_replicas
  }
}