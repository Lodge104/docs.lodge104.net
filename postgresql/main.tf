# Aurora Serverless v2 PostgreSQL Database with Lightsail VPC Peering Support
# 
# This configuration creates a cost-optimized Aurora Serverless v2 PostgreSQL database
# that can be accessed from Amazon Lightsail container services via VPC Peering.
#
# Prerequisites:
# 1. VPC Peering must be enabled for Lightsail in your AWS region
# 2. See: https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-how-to-set-up-vpc-peering-with-aws-resources.html
#
# Benefits of VPC Peering vs Public Access:
# - More secure (no public internet exposure)
# - Lower latency
# - No data transfer charges between Lightsail and VPC
# - Database remains in private subnets

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate a random password for the database
resource "random_password" "wiki_db_password" {
  length  = 16
  special = true
}

# Get default VPC and subnets to minimize costs
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# DB subnet group using default VPC subnets (accessible via VPC Peering)
resource "aws_db_subnet_group" "wiki_subnet_group" {
  name       = "wiki-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name        = "Wiki DB subnet group"
    Environment = var.environment
    Project     = "wiki"
  }
}

# Security group for Aurora cluster
resource "aws_security_group" "wiki_aurora_sg" {
  name_prefix = "wiki-aurora-sg"
  vpc_id      = data.aws_vpc.default.id

  # Allow access from VPC
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
    description = "PostgreSQL access from VPC"
  }

  # Conditional access for Lightsail container services via VPC Peering
  dynamic "ingress" {
    for_each = var.allow_lightsail_access ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.lightsail_cidr_blocks
      description = "PostgreSQL access from Amazon Lightsail container services via VPC Peering"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Wiki Aurora Security Group"
    Environment = var.environment
    Project     = "wiki"
  }
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "rds-enhanced-monitoring-role-wiki"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "RDS Enhanced Monitoring Role"
    Environment = var.environment
    Project     = "wiki"
  }
}

# Attach the AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Aurora cluster parameter group for PostgreSQL
resource "aws_rds_cluster_parameter_group" "wiki_cluster_pg" {
  family = "aurora-postgresql15"
  name   = "wiki-cluster-pg"

  # Cost optimization parameters
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Name        = "Wiki Cluster Parameter Group"
    Environment = var.environment
    Project     = "wiki"
  }
}

# Aurora Serverless v2 cluster
resource "aws_rds_cluster" "wiki_cluster" {
  cluster_identifier = "wiki-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = "wiki"
  master_username    = var.db_username
  master_password    = random_password.wiki_db_password.result

  # Cost optimization settings
  backup_retention_period      = 1 # Minimum backup retention (1 day)
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Serverless v2 scaling configuration - minimum for cost optimization
  serverlessv2_scaling_configuration {
    max_capacity = var.max_capacity
    min_capacity = var.min_capacity
  }

  # Network and security
  db_subnet_group_name            = aws_db_subnet_group.wiki_subnet_group.name
  vpc_security_group_ids          = [aws_security_group.wiki_aurora_sg.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.wiki_cluster_pg.name

  # Security features
  storage_encrypted     = var.storage_encrypted
  copy_tags_to_snapshot = true
  deletion_protection   = false # Allow deletion to avoid accidental costs
  skip_final_snapshot   = true  # Skip final snapshot for cost savings

  # Enhanced logging for better monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name        = "Wiki Aurora Cluster"
    Environment = var.environment
    Project     = "wiki"
  }
}

# Aurora Serverless v2 instance
resource "aws_rds_cluster_instance" "wiki_instance" {
  identifier         = "wiki-aurora-instance"
  cluster_identifier = aws_rds_cluster.wiki_cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.wiki_cluster.engine
  engine_version     = aws_rds_cluster.wiki_cluster.engine_version

  # Make publicly accessible for Lightsail container services
  publicly_accessible = var.publicly_accessible

  # Enhanced monitoring
  monitoring_interval = var.enhanced_monitoring_interval
  monitoring_role_arn = var.enhanced_monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring.arn : null

  # Performance Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  tags = {
    Name        = "Wiki Aurora Instance"
    Environment = var.environment
    Project     = "wiki"
  }
}

# Store password in AWS Systems Manager Parameter Store (secure and free)
resource "aws_ssm_parameter" "wiki_db_password" {
  name  = "/wiki/database/password"
  type  = "SecureString"
  value = random_password.wiki_db_password.result

  tags = {
    Name        = "Wiki Database Password"
    Environment = var.environment
    Project     = "wiki"
  }
}
