variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1" # Generally the cheapest region
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 0.5 # Minimum possible for cost optimization
}

variable "max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (ACUs)"
  type        = number
  default     = 1.0 # Keep low for cost optimization
}

variable "allow_lightsail_access" {
  description = "Allow access from Amazon Lightsail container services via VPC Peering"
  type        = bool
  default     = true
}

variable "lightsail_cidr_blocks" {
  description = "CIDR blocks for Amazon Lightsail services (via VPC Peering)"
  type        = list(string)
  default = [
    "172.26.0.0/16" # Lightsail default VPC CIDR range
  ]
}

variable "publicly_accessible" {
  description = "Make the database publicly accessible (not needed with VPC Peering)"
  type        = bool
  default     = false
}
