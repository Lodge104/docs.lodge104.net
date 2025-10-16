# Wiki.js on AWS EKS with Terraform

This repository contains Terraform infrastructure as code (IaC) to deploy [Wiki.js](https://js.wiki/) on AWS using Elastic Kubernetes Service (EKS). The configuration is optimized for minimal costs while maintaining production-grade reliability.

## Architecture

- **EKS Cluster**: Single-node Kubernetes cluster (t3.small instance)
- **Database**: PostgreSQL RDS (db.t3.micro instance)
- **Networking**: VPC with public/private subnets across 2 availability zones
- **Load Balancer**: AWS Application Load Balancer for Wiki.js access

## Prerequisites

Before you begin, ensure you have:

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (version >= 1.0)
   ```bash
   # Install Terraform (example for Linux)
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```
3. **AWS CLI** configured with credentials
   ```bash
   aws configure
   ```
4. **kubectl** installed for Kubernetes cluster management
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Lodge104/docs.lodge104.net.git
cd docs.lodge104.net
```

### 2. Configure Variables

Copy the example variables file and update with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `db_password`: Strong password for PostgreSQL database
- `wikijs_admin_email`: Your admin email address
- `aws_region`: AWS region (default: us-east-1)

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment. This process takes approximately 15-20 minutes.

### 6. Configure kubectl

After deployment completes, configure kubectl to access your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name wikijs-cluster
```

### 7. Get Wiki.js URL

Wait a few minutes for the LoadBalancer to provision, then get the URL:

```bash
kubectl get svc wikijs -n wikijs
```

Look for the `EXTERNAL-IP` column. The URL will be: `http://<EXTERNAL-IP>`

Alternatively, use:
```bash
kubectl get svc wikijs -n wikijs -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 8. Access Wiki.js

Open the LoadBalancer URL in your browser and complete the Wiki.js setup wizard.

## Cost Estimation

Monthly costs (approximate, as of 2024):

- **EKS Cluster Control Plane**: ~$73/month
- **EC2 Instance (t3.small)**: ~$15/month
- **RDS PostgreSQL (db.t3.micro)**: ~$15/month
- **Data Transfer & Storage**: ~$5-10/month
- **NAT Gateway**: ~$32/month

**Total**: ~$140-145/month

### Cost Optimization Tips

1. **Use Spot Instances**: Modify node group to use spot instances (50-70% savings)
2. **Fargate**: Consider EKS Fargate for even more cost-effective compute
3. **Reserved Instances**: For long-term usage, purchase reserved instances
4. **Stop Non-Production**: For dev/test, stop resources when not in use

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region | us-east-1 | No |
| `cluster_name` | EKS cluster name | wikijs-cluster | No |
| `environment` | Environment name | production | No |
| `db_password` | PostgreSQL password | - | Yes |
| `wikijs_admin_email` | Admin email | - | Yes |
| `node_instance_type` | EC2 instance type | t3.small | No |
| `desired_capacity` | Desired nodes | 1 | No |
| `min_capacity` | Minimum nodes | 1 | No |
| `max_capacity` | Maximum nodes | 2 | No |
| `db_instance_class` | RDS instance class | db.t3.micro | No |
| `db_allocated_storage` | RDS storage (GB) | 20 | No |

## Maintenance

### Updating Wiki.js

To update Wiki.js to a newer version:

```bash
kubectl set image deployment/wikijs wikijs=ghcr.io/requarks/wiki:2 -n wikijs
kubectl rollout restart deployment/wikijs -n wikijs
```

### Viewing Logs

```bash
kubectl logs -f deployment/wikijs -n wikijs
```

### Scaling

To scale the Wiki.js deployment:

```bash
kubectl scale deployment/wikijs --replicas=2 -n wikijs
```

## Cleanup

To destroy all resources and avoid ongoing costs:

```bash
terraform destroy
```

Type `yes` when prompted to confirm.

## Troubleshooting

### Pod Not Starting

Check pod status and logs:
```bash
kubectl get pods -n wikijs
kubectl describe pod <pod-name> -n wikijs
kubectl logs <pod-name> -n wikijs
```

### Database Connection Issues

Verify database secret:
```bash
kubectl get secret wikijs-db-secret -n wikijs -o yaml
```

Check security group rules allow traffic from EKS to RDS.

### LoadBalancer Not Provisioning

Check service status:
```bash
kubectl describe svc wikijs -n wikijs
```

Ensure AWS Load Balancer Controller is functioning properly.

## Security Considerations

1. **Database Credentials**: Stored as Kubernetes secrets, not in plain text
2. **Network Isolation**: RDS in private subnets, not publicly accessible
3. **HTTPS**: Configure SSL/TLS certificate for production use
4. **Backups**: Enable automated RDS backups in production
5. **Updates**: Regularly update EKS, Wiki.js, and dependencies

## References

- [Wiki.js Documentation](https://docs.requarks.io/)
- [Wiki.js Kubernetes Installation](https://docs.requarks.io/install/kubernetes)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This infrastructure code is provided as-is for deploying Wiki.js on AWS.

## Support

For issues or questions:
- Wiki.js: https://github.com/requarks/wiki
- Infrastructure: Create an issue in this repository