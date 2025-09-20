# ElastiCache Redis for LiteLLM and Lago
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.customer_name}-cache-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids

  tags = local.common_tags
}

resource "aws_elasticache_parameter_group" "redis7" {
  family = "redis7"
  name   = "${var.customer_name}-redis7-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = local.common_tags
}

# Redis cluster for LiteLLM
resource "aws_elasticache_replication_group" "litellm" {
  replication_group_id       = "${var.customer_name}-litellm-redis"
  description                = "Redis cluster for LiteLLM caching"

  # Node configuration
  node_type               = "cache.t3.micro"
  port                    = 6379
  parameter_group_name    = aws_elasticache_parameter_group.redis7.name

  # Cluster configuration
  num_cache_clusters      = 2
  automatic_failover_enabled = true
  multi_az_enabled        = true

  # Network configuration
  subnet_group_name       = aws_elasticache_subnet_group.main.name
  security_group_ids      = [aws_security_group.elasticache.id]

  # Backup configuration
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  maintenance_window      = "sun:05:00-sun:07:00"

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-litellm-redis"
  })
}

# Separate Redis cluster for Lago
resource "aws_elasticache_replication_group" "lago" {
  replication_group_id       = "${var.customer_name}-lago-redis"
  description                = "Redis cluster for Lago background jobs"

  # Node configuration
  node_type               = "cache.t3.micro"
  port                    = 6379
  parameter_group_name    = aws_elasticache_parameter_group.redis7.name

  # Cluster configuration
  num_cache_clusters      = 2
  automatic_failover_enabled = true
  multi_az_enabled        = true

  # Network configuration
  subnet_group_name       = aws_elasticache_subnet_group.main.name
  security_group_ids      = [aws_security_group.elasticache.id]

  # Backup configuration
  snapshot_retention_limit = 5
  snapshot_window         = "03:00-05:00"
  maintenance_window      = "sun:05:00-sun:07:00"

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.lago_redis_auth_token.result

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-lago-redis"
  })
}

# Security group for ElastiCache
resource "aws_security_group" "elasticache" {
  name_prefix = "${var.customer_name}-elasticache-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [
      module.security_groups.eks_worker_nodes_security_group_id,
      aws_security_group.litellm_service.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-elasticache-sg"
  })
}

# Security group for LiteLLM service
resource "aws_security_group" "litellm_service" {
  name_prefix = "${var.customer_name}-litellm-service-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [module.security_groups.eks_worker_nodes_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.customer_name}-litellm-service-sg"
  })
}

# Random passwords for Redis
resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

resource "random_password" "lago_redis_auth_token" {
  length  = 32
  special = false
}