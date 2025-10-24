output "cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.wiki_cluster.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.wiki_cluster.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.wiki_cluster.port
}

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.wiki_cluster.database_name
}

output "master_username" {
  description = "Database master username"
  value       = aws_rds_cluster.wiki_cluster.master_username
  sensitive   = false
}

output "password_parameter_name" {
  description = "AWS Systems Manager parameter name containing the database password"
  value       = aws_ssm_parameter.wiki_db_password.name
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.wiki_cluster.cluster_identifier
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost information"
  value       = "Estimated cost: $6-15/month (0.5-1.0 ACU * $0.50/ACU/hour * 24h * 30d = $180-360/month, but Serverless v2 scales to zero when not in use, significantly reducing actual costs)"
}

output "lightsail_connection_info" {
  description = "Information for connecting from Amazon Lightsail container services via VPC Peering"
  value = {
    enabled              = var.allow_lightsail_access
    publicly_accessible  = var.publicly_accessible
    vpc_peering_required = true
    connection_string    = "postgresql://${aws_rds_cluster.wiki_cluster.master_username}:<password>@${aws_rds_cluster.wiki_cluster.endpoint}:${aws_rds_cluster.wiki_cluster.port}/${aws_rds_cluster.wiki_cluster.database_name}"
    password_retrieval   = "aws ssm get-parameter --name '${aws_ssm_parameter.wiki_db_password.name}' --with-decryption --query 'Parameter.Value' --output text"
    setup_note           = "Ensure VPC Peering is enabled for Lightsail in your AWS region"
  }
}

output "security_group_id" {
  description = "Security group ID for the Aurora cluster"
  value       = aws_security_group.wiki_aurora_sg.id
}
