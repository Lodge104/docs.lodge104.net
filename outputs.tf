output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.wikijs.endpoint
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.wikijs.db_name
}

output "configure_kubectl" {
  description = "Configure kubectl command"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "wikijs_url" {
  description = "Wiki.js URL (once LoadBalancer is provisioned)"
  value       = "Run: kubectl get svc wikijs -n wikijs -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
