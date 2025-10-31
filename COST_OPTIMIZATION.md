# Cost Optimization Guide

This guide helps you minimize AWS costs while running Wiki.js on EKS.

## Current Cost Breakdown (Monthly)

| Service | Configuration | Approximate Cost |
|---------|--------------|------------------|
| EKS Control Plane | Standard | $73.00 |
| EC2 (t3.small) | 1 node, 2vCPU, 2GB RAM | $15.00 |
| RDS PostgreSQL (db.t3.micro) | 2vCPU, 1GB RAM, 20GB storage | $15.00 |
| NAT Gateway | Data processing + hourly | $32.00 |
| EBS Storage | 20GB gp2 | $2.00 |
| Data Transfer | 10GB out | $1.00 |
| **Total** | | **~$138/month** |

## Cost Optimization Strategies

### 1. Use Spot Instances (Save 50-70%)

Replace on-demand instances with spot instances:

**Update main.tf:**
```hcl
resource "aws_eks_node_group" "main" {
  # ... existing configuration ...
  
  capacity_type  = "SPOT"  # Add this line
  instance_types = ["t3.small", "t3a.small", "t2.small"]  # Add alternatives
}
```

**Savings**: ~$10/month on compute

### 2. Use Fargate Instead of Managed Nodes

For very small workloads, EKS Fargate can be more cost-effective:

**Create fargate-profile.tf:**
```hcl
resource "aws_eks_fargate_profile" "wikijs" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "wikijs-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = aws_subnet.private[*].id

  selector {
    namespace = "wikijs"
  }
}
```

**Savings**: Pay only for running pods, no idle node costs

### 3. Remove NAT Gateway (Save $32/month)

For test environments, use public subnets:

**Update main.tf:**
```hcl
# Comment out NAT Gateway resources
# resource "aws_nat_gateway" "main" { ... }
# resource "aws_eip" "nat" { ... }

# Update private subnet route to use IGW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id  # Changed from nat_gateway_id
  }
}

# Add map_public_ip_on_launch to private subnets
resource "aws_subnet" "private" {
  # ... existing configuration ...
  map_public_ip_on_launch = true  # Add this
}
```

**Savings**: $32/month  
**Trade-off**: Reduced security, nodes have public IPs

### 4. Use Smaller RDS Instance

For low traffic wikis:

**Update variables.tf default:**
```hcl
variable "db_instance_class" {
  default = "db.t4g.micro"  # ARM-based, cheaper
}
```

**Savings**: ~$5/month

### 5. Enable RDS Storage Autoscaling

Pay only for storage used:

**Update main.tf:**
```hcl
resource "aws_db_instance" "wikijs" {
  # ... existing configuration ...
  
  allocated_storage     = 10  # Start smaller
  max_allocated_storage = 100 # Auto-scale up to this
}
```

**Savings**: ~$1-2/month initially

### 6. Use Reserved Instances (Long-term)

For 1-year commitment:

```bash
# Purchase RI for EC2
aws ec2 purchase-reserved-instances-offering \
  --reserved-instances-offering-id <offering-id> \
  --instance-count 1

# Purchase RI for RDS
aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id <offering-id> \
  --db-instance-count 1
```

**Savings**: 30-40% on compute

### 7. Use Savings Plans

AWS Compute Savings Plans offer flexibility:

```bash
# View recommendations
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT
```

**Savings**: Up to 72% on compute

### 8. Reduce Storage Costs

**Use GP3 instead of GP2:**
```hcl
resource "aws_db_instance" "wikijs" {
  storage_type = "gp3"  # Changed from gp2
}
```

**Savings**: ~20% on storage

### 9. Implement Auto-Shutdown for Dev/Test

**Create Lambda function to stop resources:**
```python
import boto3
import os

def lambda_handler(event, context):
    eks = boto3.client('eks')
    rds = boto3.client('rds')
    
    # Scale node group to 0
    eks.update_nodegroup_config(
        clusterName=os.environ['CLUSTER_NAME'],
        nodegroupName=os.environ['NODEGROUP_NAME'],
        scalingConfig={'minSize': 0, 'maxSize': 0, 'desiredSize': 0}
    )
    
    # Stop RDS
    rds.stop_db_instance(DBInstanceIdentifier=os.environ['DB_INSTANCE'])
```

**Schedule with EventBridge:**
```bash
# Stop at 6 PM weekdays
aws events put-rule \
  --name stop-wikijs-nightly \
  --schedule-expression "cron(0 18 ? * MON-FRI *)"

# Start at 8 AM weekdays
aws events put-rule \
  --name start-wikijs-morning \
  --schedule-expression "cron(0 8 ? * MON-FRI *)"
```

**Savings**: ~60% for dev/test (12h/day, 5 days/week)

### 10. Use Single AZ (Lower Availability)

For non-production:

**Update main.tf:**
```hcl
resource "aws_subnet" "public" {
  count = 1  # Changed from 2
  # ...
}

resource "aws_subnet" "private" {
  count = 1  # Changed from 2
  # ...
}
```

**Savings**: Halve data transfer costs

## Alternative Architectures

### Architecture 1: EKS + Fargate + Aurora Serverless v2

**Cost**: ~$100/month  
**Best for**: Variable traffic, occasional use

```hcl
# Use Fargate instead of node group
# Use Aurora Serverless v2 for database
resource "aws_rds_cluster" "wikijs" {
  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"
  engine_version = "15.2"
  
  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }
}
```

### Architecture 2: ECS Fargate + RDS

**Cost**: ~$40/month  
**Best for**: Minimal traffic, testing

```hcl
# Replace EKS with ECS Fargate
# No EKS control plane costs
resource "aws_ecs_cluster" "wikijs" {
  name = "wikijs-cluster"
}

resource "aws_ecs_service" "wikijs" {
  launch_type = "FARGATE"
  # ...
}
```

### Architecture 3: Lightsail (Simplest)

**Cost**: ~$20/month  
**Best for**: Personal use, very low traffic

```bash
# Create Lightsail instance
aws lightsail create-instances \
  --instance-names wikijs \
  --availability-zone us-east-1a \
  --blueprint-id ubuntu_20_04 \
  --bundle-id medium_2_0

# Deploy Wiki.js with Docker
```

## Cost Monitoring Tools

### 1. AWS Cost Explorer

```bash
# Get current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "1 day ago" +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=SERVICE
```

### 2. CloudWatch Billing Alarms

```bash
# Create alarm for monthly costs > $150
aws cloudwatch put-metric-alarm \
  --alarm-name wiki-monthly-cost \
  --alarm-description "Monthly Wiki.js costs" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 150 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

### 3. AWS Budgets

```bash
# Create monthly budget
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json

# budget.json
{
  "BudgetName": "WikiJS-Monthly",
  "BudgetLimit": {
    "Amount": "150",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### 4. Third-Party Tools

- **Kubecost**: Kubernetes cost allocation
- **CloudHealth**: Multi-cloud cost management
- **Infracost**: Terraform cost estimation

## Recommended Configuration by Use Case

### Personal Blog ($40/month)
```hcl
node_instance_type    = "t3.micro"
desired_capacity      = 1
db_instance_class     = "db.t4g.micro"
capacity_type         = "SPOT"
# Remove NAT Gateway
```

### Small Team Wiki ($80/month)
```hcl
node_instance_type    = "t3.small"
desired_capacity      = 1
db_instance_class     = "db.t3.small"
# Use Fargate profile
# Keep NAT Gateway for security
```

### Medium Organization ($150/month)
```hcl
node_instance_type    = "t3.medium"
desired_capacity      = 2
db_instance_class     = "db.t3.small"
# Multi-AZ RDS
# Reserved Instances
```

### Enterprise ($300+/month)
```hcl
node_instance_type    = "t3.large"
desired_capacity      = 3
db_instance_class     = "db.r6g.large"
# Multi-region setup
# Aurora PostgreSQL
# Auto-scaling enabled
```

## Cost Optimization Checklist

- [ ] Enable AWS Cost Explorer
- [ ] Set up billing alarms
- [ ] Review instance types monthly
- [ ] Check for idle resources
- [ ] Enable auto-scaling
- [ ] Use Spot instances for non-critical workloads
- [ ] Consider Fargate for variable workloads
- [ ] Remove unused EBS volumes
- [ ] Delete old RDS snapshots
- [ ] Optimize data transfer
- [ ] Use VPC endpoints for AWS services
- [ ] Enable S3 lifecycle policies
- [ ] Review CloudWatch logs retention
- [ ] Use Reserved Instances for steady state
- [ ] Enable RDS storage autoscaling

## Monthly Cost Review Template

```bash
#!/bin/bash
# monthly-cost-review.sh

echo "=== Wiki.js Cost Review ==="
echo "Date: $(date)"
echo

# EKS Cluster
echo "EKS Nodes:"
kubectl get nodes
echo

# RDS Instance
echo "RDS Status:"
aws rds describe-db-instances \
  --db-instance-identifier wikijs-cluster-db \
  --query 'DBInstances[0].[DBInstanceStatus,DBInstanceClass]' \
  --output text
echo

# Current Month Cost
echo "Current Month Cost:"
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table
echo

# Recommendations
echo "Cost Optimization Opportunities:"
aws compute-optimizer get-ec2-instance-recommendations \
  --query 'InstanceRecommendations[*].[InstanceName,CurrentInstanceType,RecommendationOptions[0].InstanceType]' \
  --output table
```

Run monthly to identify savings opportunities.

## Additional Resources

- [AWS Cost Optimization](https://aws.amazon.com/pricing/cost-optimization/)
- [EKS Best Practices - Cost Optimization](https://aws.github.io/aws-eks-best-practices/cost_optimization/)
- [Kubecost Documentation](https://docs.kubecost.com/)
- [AWS Pricing Calculator](https://calculator.aws/)

---

**Questions?** Open an issue or contribute your cost-saving tips!
