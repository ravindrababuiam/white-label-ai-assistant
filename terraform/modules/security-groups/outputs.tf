# Security Groups Module Outputs

output "eks_control_plane_security_group_id" {
  description = "Security group ID for EKS control plane"
  value       = aws_security_group.eks_control_plane.id
}

output "eks_worker_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_worker_nodes.id
}

output "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "open_webui_security_group_id" {
  description = "Security group ID for Open WebUI"
  value       = aws_security_group.open_webui.id
}

output "ollama_security_group_id" {
  description = "Security group ID for Ollama"
  value       = aws_security_group.ollama.id
}

output "qdrant_security_group_id" {
  description = "Security group ID for Qdrant"
  value       = aws_security_group.qdrant.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}