provider "aws" {
  region = var.aws_region
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.cluster_name}-vpc"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.cluster_name}-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-${count.index + 1}"
    Environment                                 = var.environment
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private Subnets (using public IPs for internet access without NAT Gateway)
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-private-${count.index + 1}"
    Environment                                 = var.environment
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.cluster_name}-public-rt"
    Environment = var.environment
  }
}

# Private Route Table (using Internet Gateway directly, no NAT Gateway for cost savings)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.cluster_name}-private-rt"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.cluster_name}-eks-cluster-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-eks-cluster-sg"
    Environment = var.environment
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }
}

# Fargate Pod Execution IAM Role
resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.cluster_name}-fargate-pod-execution-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution.arn
}

# Fargate Profile for Wiki.js
resource "aws_eks_fargate_profile" "wikijs" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "wikijs-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = aws_subnet.private[*].id

  selector {
    namespace = "wikijs"
  }

  tags = {
    Name        = "${var.cluster_name}-wikijs-fargate-profile"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution_policy,
  ]
}

# Fargate Profile for CoreDNS
resource "aws_eks_fargate_profile" "coredns" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "coredns-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = aws_subnet.private[*].id

  selector {
    namespace = "kube-system"
    labels = {
      k8s-app = "kube-dns"
    }
  }

  tags = {
    Name        = "${var.cluster_name}-coredns-fargate-profile"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution_policy,
  ]
}

# Aurora Subnet Group
resource "aws_db_subnet_group" "wikijs" {
  name       = "${var.cluster_name}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.cluster_name}-db-subnet"
    Environment = var.environment
  }
}

# Aurora Security Group
resource "aws_security_group" "aurora" {
  name        = "${var.cluster_name}-aurora-sg"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-aurora-sg"
    Environment = var.environment
  }
}

# Aurora PostgreSQL Serverless v2 Cluster
resource "aws_rds_cluster" "wikijs" {
  cluster_identifier      = "${var.cluster_name}-aurora-cluster"
  engine                  = "aurora-postgresql"
  engine_mode             = "provisioned"
  engine_version          = "15.4"
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.wikijs.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  skip_final_snapshot     = true
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"

  serverlessv2_scaling_configuration {
    max_capacity = var.aurora_max_capacity
    min_capacity = var.aurora_min_capacity
  }

  tags = {
    Name        = "${var.cluster_name}-aurora-cluster"
    Environment = var.environment
  }
}

# Aurora PostgreSQL Serverless v2 Instance
resource "aws_rds_cluster_instance" "wikijs" {
  cluster_identifier  = aws_rds_cluster.wikijs.id
  identifier          = "${var.cluster_name}-aurora-instance"
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.wikijs.engine
  engine_version      = aws_rds_cluster.wikijs.engine_version
  publicly_accessible = false

  tags = {
    Name        = "${var.cluster_name}-aurora-instance"
    Environment = var.environment
  }
}

# Configure Kubernetes provider
data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Create namespace for Wiki.js
resource "kubernetes_namespace" "wikijs" {
  metadata {
    name = "wikijs"
  }

  depends_on = [aws_eks_fargate_profile.wikijs]
}

# Create secret for database credentials
resource "kubernetes_secret" "wikijs_db" {
  metadata {
    name      = "wikijs-db-secret"
    namespace = kubernetes_namespace.wikijs.metadata[0].name
  }

  data = {
    DB_TYPE = "postgres"
    DB_HOST = aws_rds_cluster.wikijs.endpoint
    DB_PORT = "5432"
    DB_USER = var.db_username
    DB_PASS = var.db_password
    DB_NAME = var.db_name
  }

  type = "Opaque"
}

# Wiki.js Deployment
resource "kubernetes_deployment" "wikijs" {
  metadata {
    name      = "wikijs"
    namespace = kubernetes_namespace.wikijs.metadata[0].name
    labels = {
      app = "wikijs"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wikijs"
      }
    }

    template {
      metadata {
        labels = {
          app = "wikijs"
        }
      }

      spec {
        container {
          name  = "wikijs"
          image = "ghcr.io/requarks/wiki:2"

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name = "DB_TYPE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_TYPE"
              }
            }
          }

          env {
            name = "DB_HOST"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_HOST"
              }
            }
          }

          env {
            name = "DB_PORT"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_PORT"
              }
            }
          }

          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_PASS"
              }
            }
          }

          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.wikijs_db.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    aws_rds_cluster.wikijs,
    aws_rds_cluster_instance.wikijs,
    kubernetes_secret.wikijs_db
  ]
}

# Wiki.js Service
resource "kubernetes_service" "wikijs" {
  metadata {
    name      = "wikijs"
    namespace = kubernetes_namespace.wikijs.metadata[0].name
  }

  spec {
    selector = {
      app = "wikijs"
    }

    port {
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.wikijs]
}
