# OIDC Provider Module
# Creates OIDC identity provider for EKS cluster to enable IAM roles for service accounts

# Data source to get the OIDC issuer thumbprint
data "tls_certificate" "eks_oidc_issuer" {
  url = var.oidc_issuer_url
}

# OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc_issuer.certificates[0].sha1_fingerprint]
  url             = var.oidc_issuer_url

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-eks-oidc-provider"
  })
}