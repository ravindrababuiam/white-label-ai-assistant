# EKS Cluster Module
# Creates EKS cluster with managed node groups for customer workloads

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.customer_name}-eks-cluster"
  role_arn = var.cluster_service_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [var.control_plane_security_group_id]
  }

  # Enable EKS Cluster logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling
  depends_on = [
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-eks-cluster"
  })
}

# CloudWatch Log Group for EKS Cluster Logs
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.customer_name}-eks-cluster/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-eks-cluster-logs"
  })
}

# EKS Node Group for general workloads
resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.customer_name}-general-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  # Disk configuration
  disk_size = var.node_disk_size

  # AMI type
  ami_type = var.node_ami_type

  # Remote access configuration
  dynamic "remote_access" {
    for_each = var.enable_node_ssh_access ? [1] : []
    content {
      ec2_ssh_key               = var.node_ssh_key_name
      source_security_group_ids = [var.worker_nodes_security_group_id]
    }
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling
  depends_on = [
    aws_eks_cluster.main
  ]

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-general-nodes"
  })

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# EKS Node Group for GPU workloads (Ollama)
resource "aws_eks_node_group" "gpu" {
  count = var.enable_gpu_nodes ? 1 : 0

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.customer_name}-gpu-nodes"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = var.gpu_instance_types

  scaling_config {
    desired_size = var.gpu_node_desired_size
    max_size     = var.gpu_node_max_size
    min_size     = var.gpu_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  # Disk configuration for GPU nodes (larger for model storage)
  disk_size = var.gpu_node_disk_size

  # AMI type for GPU
  ami_type = "AL2_x86_64_GPU"

  # Taints for GPU nodes
  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  # Remote access configuration
  dynamic "remote_access" {
    for_each = var.enable_node_ssh_access ? [1] : []
    content {
      ec2_ssh_key               = var.node_ssh_key_name
      source_security_group_ids = [var.worker_nodes_security_group_id]
    }
  }

  depends_on = [
    aws_eks_cluster.main
  ]

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-gpu-nodes"
    "k8s.io/cluster-autoscaler/node-template/taint/nvidia.com/gpu" = "true:NoSchedule"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# EKS Add-ons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.general
  ]

  tags = var.common_tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags
}