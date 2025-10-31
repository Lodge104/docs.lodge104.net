# Deployment Guide

This guide provides step-by-step instructions for deploying Wiki.js on AWS EKS.

## Pre-Deployment Checklist

- [ ] AWS account with administrative access
- [ ] AWS CLI installed and configured
- [ ] Terraform installed (>= 1.0)
- [ ] kubectl installed
- [ ] Git repository cloned locally

## Step 1: Configure AWS Credentials

```bash
# Configure AWS CLI with your credentials
aws configure

# Verify credentials
aws sts get-caller-identity
```

## Step 2: Prepare Configuration

```bash
# Navigate to repository
cd docs.lodge104.net

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# Required:
# - db_password: Strong password for PostgreSQL
# - wikijs_admin_email: Your admin email
nano terraform.tfvars
```

### Recommended Configuration

For cost optimization, use these settings in `terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
cluster_name       = "wikijs-cluster"
environment        = "production"
node_instance_type = "t3.small"
desired_capacity   = 1
min_capacity       = 1
max_capacity       = 2
db_instance_class  = "db.t3.micro"
db_allocated_storage = 20
```

## Step 3: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

## Step 4: Review Infrastructure Plan

```bash
terraform plan
```

Review the output to ensure:
- Approximately 30-35 resources will be created
- VPC with public/private subnets
- EKS cluster with 1 node
- RDS PostgreSQL instance
- Kubernetes resources for Wiki.js

## Step 5: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 15-20 minutes.

### What's Being Created

1. **VPC Infrastructure** (~2 minutes)
   - VPC with CIDR 10.0.0.0/16
   - 2 public subnets
   - 2 private subnets
   - Internet Gateway
   - Route tables (no NAT Gateway for cost optimization)

2. **EKS Cluster** (~10 minutes)
   - EKS control plane
   - IAM roles and policies
   - Security groups

3. **Fargate Profiles** (~5 minutes)
   - EC2 instance (t3.small)
   - Auto-scaling configuration

4. **RDS PostgreSQL** (~5 minutes)
   - Database instance (db.t3.micro)
   - Security group
   - Subnet group

5. **Kubernetes Resources** (~2 minutes)
   - Namespace
   - Secrets
   - Deployment
   - Service (LoadBalancer)

## Step 6: Configure kubectl

After successful deployment:

```bash
# Configure kubectl to access the cluster
aws eks update-kubeconfig --region us-east-1 --name wikijs-cluster

# Verify cluster access
kubectl cluster-info

# Check nodes
kubectl get nodes
```

Expected output:
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-x-x.ec2.internal     Ready    <none>   5m    v1.27.x
```

## Step 7: Monitor Deployment

```bash
# Check namespace
kubectl get namespaces

# Check Wiki.js pod status
kubectl get pods -n wikijs

# Watch pod startup (Ctrl+C to exit)
kubectl get pods -n wikijs -w

# Check pod logs
kubectl logs -f deployment/wikijs -n wikijs
```

Wait for pod status to be `Running` and `Ready 1/1`.

## Step 8: Get Wiki.js URL

```bash
# Get service details
kubectl get svc wikijs -n wikijs

# Get LoadBalancer hostname
kubectl get svc wikijs -n wikijs -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The LoadBalancer may take 2-3 minutes to provision. If `EXTERNAL-IP` shows `<pending>`, wait and retry.

## Step 9: Access Wiki.js

1. Copy the LoadBalancer hostname from Step 8
2. Open in a web browser: `http://<loadbalancer-hostname>`
3. Complete the Wiki.js setup wizard:
   - Choose "Local Database" (already configured)
   - Set administrator email
   - Set administrator password
   - Configure site settings

## Step 10: Verify Installation

After completing the setup:

1. Log in with administrator credentials
2. Create a test page
3. Verify database connectivity
4. Check system information in Admin panel

## Post-Deployment Tasks

### Enable HTTPS (Recommended)

For production use, configure SSL/TLS:

1. **Option A: AWS Certificate Manager + ALB Ingress Controller**
   ```bash
   # Install AWS Load Balancer Controller
   kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
   
   # Configure ingress with ACM certificate
   # (see ingress-https.yaml example)
   ```

2. **Option B: Let's Encrypt + cert-manager**
   ```bash
   # Install cert-manager
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   
   # Configure ClusterIssuer and Certificate
   # (see cert-manager-setup.yaml example)
   ```

### Configure Backups

Enable automated RDS backups:

```bash
# Edit RDS instance to enable automated backups
aws rds modify-db-instance \
  --db-instance-identifier wikijs-cluster-db \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --apply-immediately
```

### Set Up Monitoring

1. **CloudWatch Logs**
   ```bash
   # Enable EKS control plane logging
   aws eks update-cluster-config \
     --name wikijs-cluster \
     --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
   ```

2. **CloudWatch Container Insights**
   ```bash
   # Deploy CloudWatch agent
   kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml
   ```

### Configure Auto-Scaling

For variable load:

```bash
# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create HorizontalPodAutoscaler
kubectl autoscale deployment wikijs -n wikijs --cpu-percent=70 --min=1 --max=3
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n wikijs

# Check logs
kubectl logs <pod-name> -n wikijs

# Common issues:
# - Database connection timeout: Check RDS security group
# - Image pull error: Check internet connectivity from private subnet
# - Resource limits: Check node resources
```

### Database Connection Failed

```bash
# Verify RDS endpoint
terraform output db_endpoint

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw cluster_security_group_id)

# Test connectivity from pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -n wikijs -- \
  psql -h <rds-endpoint> -U wikijs -d wikijs
```

### LoadBalancer Not Provisioning

```bash
# Check service status
kubectl describe svc wikijs -n wikijs

# Check events
kubectl get events -n wikijs --sort-by='.lastTimestamp'

# Verify subnet tags for ELB
aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/role/elb,Values=1"
```

### Terraform Apply Fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify region configuration
grep aws_region terraform.tfvars

# Check for quota limits
aws service-quotas list-service-quotas --service-code eks

# If resources exist, import state
terraform import aws_vpc.main <vpc-id>
```

## Maintenance

### Update Wiki.js Version

```bash
# Update to latest version
kubectl set image deployment/wikijs wikijs=ghcr.io/requarks/wiki:2 -n wikijs

# Or specific version
kubectl set image deployment/wikijs wikijs=ghcr.io/requarks/wiki:2.5.300 -n wikijs

# Monitor rollout
kubectl rollout status deployment/wikijs -n wikijs

# Rollback if needed
kubectl rollout undo deployment/wikijs -n wikijs
```

### Scale Resources

```bash
# Scale Wiki.js pods
kubectl scale deployment/wikijs --replicas=2 -n wikijs

# Scale node group (via Terraform)
# Edit terraform.tfvars: desired_capacity = 2
terraform apply
```

### Backup Database

```bash
# Manual RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier wikijs-cluster-db \
  --db-snapshot-identifier wikijs-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier wikijs-cluster-db
```

### Update Terraform

```bash
# Update providers
terraform init -upgrade

# Plan changes
terraform plan

# Apply updates
terraform apply
```

## Cleanup

To remove all resources and stop incurring costs:

```bash
# Destroy infrastructure
terraform destroy

# Verify resources are removed
aws eks list-clusters
aws rds describe-db-instances
aws ec2 describe-vpcs
```

**Warning**: This will permanently delete:
- EKS cluster and all Kubernetes resources
- RDS database and all data
- VPC and networking components
- All Wiki.js content

Ensure you have backups before destroying!

## Cost Management

### Daily Cost Monitoring

```bash
# Check AWS Cost Explorer via CLI
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost

# Set up billing alerts (one-time)
aws cloudwatch put-metric-alarm \
  --alarm-name wiki-cost-alert \
  --alarm-description "Alert when Wiki.js costs exceed $200" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 200 \
  --comparison-operator GreaterThanThreshold
```

### Stop Non-Production Environments

For development/testing:

```bash
# Stop node group (scale to 0)
aws eks update-nodegroup-config \
  --cluster-name wikijs-cluster \
  --nodegroup-name wikijs-cluster-node-group \
  --scaling-config minSize=0,maxSize=0,desiredSize=0

# Stop RDS instance
aws rds stop-db-instance --db-instance-identifier wikijs-cluster-db
```

**Note**: EKS control plane costs continue even with 0 nodes. Use terraform destroy for full cost savings.

## Support Resources

- **Wiki.js Issues**: https://github.com/requarks/wiki/issues
- **AWS EKS Documentation**: https://docs.aws.amazon.com/eks/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **Kubernetes Documentation**: https://kubernetes.io/docs/

## Next Steps

After successful deployment:

1. Configure Wiki.js settings
2. Set up authentication (LDAP, OAuth, SAML)
3. Configure storage providers (S3, Azure, etc.)
4. Set up SSL/TLS certificates
5. Configure backups and disaster recovery
6. Implement monitoring and alerting
7. Document your Wiki.js workflows

---

**Need help?** Create an issue in this repository with:
- Terraform version
- Error messages
- Output of `terraform plan`
- Relevant logs from `kubectl logs`
