variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "wikijs-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "db_password" {
  description = "Password for PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "wikijs_admin_email" {
  description = "Admin email for Wiki.js"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aurora_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity units (0.5 = 1GB RAM)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity units (1 = 2GB RAM)"
  type        = number
  default     = 1.0
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "wikijs"
}

variable "db_username" {
  description = "Username for PostgreSQL database"
  type        = string
  default     = "wikijs"
}
