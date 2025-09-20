# IAM Module Outputs

output "eks_cluster_service_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = aws_iam_role.eks_cluster_service_role.arn
}

output "eks_node_group_role_arn" {
  description = "ARN of the EKS node group role"
  value       = aws_iam_role.eks_node_group_role.arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller role"
  value       = var.oidc_provider_arn != "" && var.oidc_issuer_url != "" ? aws_iam_role.aws_load_balancer_controller[0].arn : ""
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI Driver role"
  value       = var.oidc_provider_arn != "" && var.oidc_issuer_url != "" ? aws_iam_role.ebs_csi_driver[0].arn : ""
}

output "s3_customer_bucket_access_policy_arn" {
  description = "ARN of the S3 customer bucket access policy"
  value       = aws_iam_policy.s3_customer_bucket_access.arn
}