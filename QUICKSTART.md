# Quick Start Guide

Deploy Wiki.js on AWS EKS in 15 minutes!

## Prerequisites

- AWS account
- AWS CLI configured
- Terraform installed
- kubectl installed

## Quick Deploy (5 Steps)

### 1. Clone & Configure

```bash
git clone https://github.com/Lodge104/docs.lodge104.net.git
cd docs.lodge104.net
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
db_password        = "YourSecurePassword123!"
wikijs_admin_email = "admin@example.com"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Preview Changes

```bash
terraform plan
```

### 4. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Wait ~15-20 minutes.

### 5. Access Wiki.js

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name wikijs-cluster

# Get Wiki.js URL (wait 2-3 minutes if pending)
kubectl get svc wikijs -n wikijs

# Open the EXTERNAL-IP in your browser
```

## What Gets Created?

- ✅ EKS Kubernetes cluster
- ✅ Single t3.small worker node
- ✅ PostgreSQL database (db.t3.micro)
- ✅ VPC with public/private subnets
- ✅ Application Load Balancer
- ✅ Wiki.js application

## Estimated Cost

**~$140/month** (can be reduced to ~$40/month with optimizations)

See [COST_OPTIMIZATION.md](./COST_OPTIMIZATION.md) for cost-saving strategies.

## Next Steps

1. **Access Wiki.js**: Open the LoadBalancer URL in your browser
2. **Complete Setup**: Follow the Wiki.js setup wizard
3. **Enable HTTPS**: See [DEPLOYMENT.md](./DEPLOYMENT.md#enable-https)
4. **Configure Backups**: See [DEPLOYMENT.md](./DEPLOYMENT.md#configure-backups)
5. **Set Up Monitoring**: See [ARCHITECTURE.md](./ARCHITECTURE.md#monitoring-and-observability)

## Troubleshooting

### LoadBalancer Shows "Pending"

Wait 2-3 minutes and check again:
```bash
kubectl get svc wikijs -n wikijs -w
```

### Pod Not Starting

Check logs:
```bash
kubectl get pods -n wikijs
kubectl logs -f deployment/wikijs -n wikijs
```

### Database Connection Error

Verify security groups allow traffic from EKS to RDS:
```bash
terraform output cluster_security_group_id
terraform output db_endpoint
```

### Terraform Apply Fails

Check AWS credentials:
```bash
aws sts get-caller-identity
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

⚠️ **Warning**: This deletes everything including the database!

## Need Help?

- 📖 [Full Deployment Guide](./DEPLOYMENT.md)
- 🏗️ [Architecture Documentation](./ARCHITECTURE.md)
- 💰 [Cost Optimization Guide](./COST_OPTIMIZATION.md)
- 🐛 [Create an Issue](https://github.com/Lodge104/docs.lodge104.net/issues)

## Common Commands

```bash
# View cluster info
kubectl cluster-info

# View all resources
kubectl get all -n wikijs

# View logs
kubectl logs -f deployment/wikijs -n wikijs

# Scale up
kubectl scale deployment/wikijs --replicas=2 -n wikijs

# Restart Wiki.js
kubectl rollout restart deployment/wikijs -n wikijs

# Get database endpoint
terraform output db_endpoint

# Get kubectl config command
terraform output configure_kubectl
```

## Wiki.js Setup Wizard

After accessing Wiki.js:

1. **Administration Email**: Use the email from terraform.tfvars
2. **Create Password**: Choose a strong administrator password
3. **Site URL**: The LoadBalancer hostname (or your domain if configured)
4. **Installation Type**: Leave default settings
5. **Click Install**: Wait for setup to complete
6. **Login**: Use your email and password

## Security Recommendations

- [ ] Change default admin password immediately
- [ ] Enable HTTPS with SSL certificate
- [ ] Configure authentication (OAuth, LDAP, SAML)
- [ ] Enable RDS automated backups
- [ ] Set up CloudWatch alarms
- [ ] Review IAM policies
- [ ] Enable VPC Flow Logs
- [ ] Configure WAF for the LoadBalancer

## Performance Tips

- Use CloudFront CDN for static assets
- Enable Redis for caching
- Use S3 for media storage
- Configure database connection pooling
- Enable horizontal pod autoscaling

---

**Ready to deploy?** Start with step 1! ☝️
