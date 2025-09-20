# Security Groups Module
# Creates security groups for different components with least-privilege access

# Security Group for EKS Control Plane
resource "aws_security_group" "eks_control_plane" {
  name_prefix = "${var.customer_name}-eks-control-plane"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-eks-control-plane-sg"
  })
}

# Security Group for EKS Worker Nodes
resource "aws_security_group" "eks_worker_nodes" {
  name_prefix = "${var.customer_name}-eks-worker-nodes"
  vpc_id      = var.vpc_id

  # Allow nodes to communicate with each other
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-eks-worker-nodes-sg"
  })
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${var.customer_name}-alb"
  vpc_id      = var.vpc_id

  # Allow HTTP traffic from internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic from internet
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-alb-sg"
  })
}

# Security Group for Open WebUI
resource "aws_security_group" "open_webui" {
  name_prefix = "${var.customer_name}-open-webui"
  vpc_id      = var.vpc_id

  # Allow traffic from ALB
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow traffic from within EKS cluster
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-open-webui-sg"
  })
}

# Security Group for Ollama
resource "aws_security_group" "ollama" {
  name_prefix = "${var.customer_name}-ollama"
  vpc_id      = var.vpc_id

  # Allow traffic from Open WebUI
  ingress {
    from_port       = 11434
    to_port         = 11434
    protocol        = "tcp"
    security_groups = [aws_security_group.open_webui.id]
  }

  # Allow traffic from within EKS cluster
  ingress {
    from_port       = 11434
    to_port         = 11434
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-ollama-sg"
  })
}

# Security Group for Qdrant Vector Database
resource "aws_security_group" "qdrant" {
  name_prefix = "${var.customer_name}-qdrant"
  vpc_id      = var.vpc_id

  # Allow HTTP API traffic from Open WebUI
  ingress {
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    security_groups = [aws_security_group.open_webui.id]
  }

  # Allow gRPC traffic from Open WebUI
  ingress {
    from_port       = 6334
    to_port         = 6334
    protocol        = "tcp"
    security_groups = [aws_security_group.open_webui.id]
  }

  # Allow traffic from within EKS cluster
  ingress {
    from_port       = 6333
    to_port         = 6334
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-qdrant-sg"
  })
}

# Security Group for RDS (if needed for future use)
resource "aws_security_group" "rds" {
  name_prefix = "${var.customer_name}-rds"
  vpc_id      = var.vpc_id

  # Allow PostgreSQL traffic from EKS worker nodes
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  # Allow MySQL traffic from EKS worker nodes
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_worker_nodes.id]
  }

  # No outbound rules needed for RDS
  tags = merge(var.common_tags, {
    Name = "${var.customer_name}-rds-sg"
  })
}
# Security Group Rules (separate to avoid circular dependencies)
resource "aws_security_group_rule" "control_plane_ingress_from_workers" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_worker_nodes.id
  security_group_id        = aws_security_group.eks_control_plane.id
}

resource "aws_security_group_rule" "workers_ingress_from_control_plane_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_control_plane.id
  security_group_id        = aws_security_group.eks_worker_nodes.id
}

resource "aws_security_group_rule" "workers_ingress_from_control_plane_kubelet" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_control_plane.id
  security_group_id        = aws_security_group.eks_worker_nodes.id
}