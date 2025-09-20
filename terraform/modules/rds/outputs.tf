output "litellm_db_endpoint" {
  description = "LiteLLM database endpoint"
  value       = aws_db_instance.litellm.endpoint
}

output "litellm_db_port" {
  description = "LiteLLM database port"
  value       = aws_db_instance.litellm.port
}

output "litellm_db_name" {
  description = "LiteLLM database name"
  value       = aws_db_instance.litellm.db_name
}

output "litellm_db_username" {
  description = "LiteLLM database username"
  value       = aws_db_instance.litellm.username
  sensitive   = true
}

output "litellm_db_password" {
  description = "LiteLLM database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "lago_db_endpoint" {
  description = "Lago database endpoint"
  value       = aws_db_instance.lago.endpoint
}

output "lago_db_port" {
  description = "Lago database port"
  value       = aws_db_instance.lago.port
}

output "lago_db_name" {
  description = "Lago database name"
  value       = aws_db_instance.lago.db_name
}

output "lago_db_username" {
  description = "Lago database username"
  value       = aws_db_instance.lago.username
  sensitive   = true
}

output "lago_db_password" {
  description = "Lago database password"
  value       = random_password.lago_db_password.result
  sensitive   = true
}

output "db_subnet_group_name" {
  description = "Database subnet group name"
  value       = aws_db_subnet_group.main.name
}