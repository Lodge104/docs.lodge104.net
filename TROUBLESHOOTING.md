# Troubleshooting Guide

This guide helps you diagnose and fix common issues with the Wiki.js EKS deployment.

## Table of Contents

- [Terraform Issues](#terraform-issues)
- [EKS Cluster Issues](#eks-cluster-issues)
- [Pod Issues](#pod-issues)
- [Database Issues](#database-issues)
- [Networking Issues](#networking-issues)
- [LoadBalancer Issues](#loadbalancer-issues)
- [Wiki.js Application Issues](#wikijs-application-issues)
- [Performance Issues](#performance-issues)

## Terraform Issues

### Error: "No valid credential sources found"

**Symptom**: Terraform fails with AWS authentication error

**Solution**:
```bash
# Configure AWS credentials
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"

# Verify
aws sts get-caller-identity
```

### Error: "Error creating EKS Cluster"

**Symptom**: EKS cluster creation fails

**Common Causes**:
1. Service quota limits
2. IAM permissions
3. VPC/subnet issues

**Solution**:
```bash
# Check EKS quota
aws service-quotas get-service-quota \
  --service-code eks \
  --quota-code L-1194D53C

# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names eks:CreateCluster

# Verify VPC configuration
terraform state show aws_vpc.main
```

### Error: "Resource already exists"

**Symptom**: Terraform apply fails because resource exists

**Solution**:
```bash
# Import existing resource
terraform import aws_vpc.main vpc-xxxxxxxxx

# Or destroy and recreate
terraform destroy
terraform apply
```

### Error: "Error locking state"

**Symptom**: State file is locked

**Solution**:
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Or wait for lock to expire (usually 15 minutes)
```

## EKS Cluster Issues

### Cluster Not Accessible

**Symptom**: `kubectl` commands fail with connection error

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name wikijs-cluster

# Verify connection
kubectl cluster-info

# Check cluster status
aws eks describe-cluster --name wikijs-cluster --query 'cluster.status'
```

### Nodes Not Ready

**Symptom**: `kubectl get nodes` shows NotReady status

**Solution**:
```bash
# Check node status
kubectl describe node <node-name>

# Check node logs
kubectl logs -n kube-system -l app=aws-node

# Restart node (via EC2)
aws ec2 reboot-instances --instance-ids <instance-id>
```

### Node Group Fails to Create

**Symptom**: Node group creation timeout or failure

**Solution**:
```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name wikijs-cluster \
  --nodegroup-name wikijs-cluster-node-group

# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?contains(Tags[?Key==`eks:cluster-name`].Value, `wikijs-cluster`)]'

# View EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=wikijs-cluster"
```

## Pod Issues

### Pod Stuck in Pending

**Symptom**: Wiki.js pod status shows Pending

**Solution**:
```bash
# Check pod events
kubectl describe pod -n wikijs <pod-name>

# Common issues:
# 1. Insufficient resources
kubectl top nodes

# 2. Image pull error
kubectl get events -n wikijs --sort-by='.lastTimestamp'

# 3. Node selector mismatch
kubectl get pod -n wikijs <pod-name> -o yaml | grep -A5 nodeSelector
```

### Pod Stuck in CrashLoopBackOff

**Symptom**: Pod continuously restarts

**Solution**:
```bash
# Check logs
kubectl logs -n wikijs <pod-name>
kubectl logs -n wikijs <pod-name> --previous

# Check events
kubectl describe pod -n wikijs <pod-name>

# Common causes:
# 1. Database connection failure (see Database Issues)
# 2. Missing environment variables
kubectl get secret -n wikijs wikijs-db-secret -o yaml

# 3. Resource limits too low
kubectl describe pod -n wikijs <pod-name> | grep -A10 Limits
```

### Pod ImagePullBackOff

**Symptom**: Cannot pull container image

**Solution**:
```bash
# Check image name
kubectl get pod -n wikijs <pod-name> -o jsonpath='{.spec.containers[0].image}'

# Verify internet connectivity from node
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- https://ghcr.io

# Check NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Verify route table
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"
```

## Database Issues

### Database Connection Refused

**Symptom**: Wiki.js cannot connect to database

**Solution**:
```bash
# 1. Verify RDS is running
aws rds describe-db-instances \
  --db-instance-identifier wikijs-cluster-db \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. Check security group
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw rds_security_group_id)

# 3. Test connectivity from pod
kubectl run -it --rm psql-test --image=postgres:15 --restart=Never -n wikijs -- \
  psql -h $(terraform output -raw db_endpoint | cut -d: -f1) \
  -U wikijs -d wikijs -c "SELECT 1;"

# 4. Verify secret
kubectl get secret -n wikijs wikijs-db-secret -o jsonpath='{.data.DB_HOST}' | base64 -d
```

### Database Connection Timeout

**Symptom**: Connection times out

**Solution**:
```bash
# Check security group rules
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(terraform output -raw rds_security_group_id)"

# Verify cluster security group ID
terraform output cluster_security_group_id

# Update RDS security group if needed
aws ec2 authorize-security-group-ingress \
  --group-id $(terraform output -raw rds_security_group_id) \
  --protocol tcp \
  --port 5432 \
  --source-group $(terraform output -raw cluster_security_group_id)
```

### Database Out of Connections

**Symptom**: "too many connections" error

**Solution**:
```sql
-- Connect to database
psql -h <db-endpoint> -U wikijs -d wikijs

-- Check current connections
SELECT count(*) FROM pg_stat_activity;

-- View max connections
SHOW max_connections;

-- Kill idle connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND state_change < now() - interval '10 minutes';
```

## Networking Issues

### NAT Gateway Not Working

**Symptom**: Nodes cannot access internet

**Solution**:
```bash
# Check NAT Gateway status
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Verify route table
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'RouteTables[*].[RouteTableId,Routes]'

# Test internet from pod
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- https://google.com
```

### DNS Resolution Failing

**Symptom**: Cannot resolve domain names

**Solution**:
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup google.com

# Restart CoreDNS if needed
kubectl rollout restart deployment/coredns -n kube-system
```

### VPC Peering Issues

**Symptom**: Cannot communicate with peered VPC

**Solution**:
```bash
# Check route table entries
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Verify security group rules
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check network ACLs
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"
```

## LoadBalancer Issues

### LoadBalancer Stuck in Pending

**Symptom**: Service EXTERNAL-IP shows `<pending>`

**Solution**:
```bash
# Check service events
kubectl describe svc wikijs -n wikijs

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system | grep aws-load-balancer

# Verify subnet tags
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'Subnets[*].[SubnetId,Tags]'

# Required tags:
# kubernetes.io/role/elb=1 (public subnets)
# kubernetes.io/cluster/<cluster-name>=shared
```

### LoadBalancer Created But Not Accessible

**Symptom**: LoadBalancer exists but cannot access Wiki.js

**Solution**:
```bash
# Get LoadBalancer details
kubectl get svc wikijs -n wikijs -o wide

# Check LoadBalancer health checks
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Verify security group
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,SecurityGroups]'

# Check pod readiness
kubectl get pods -n wikijs -o wide
```

### 503 Service Unavailable

**Symptom**: LoadBalancer returns 503 error

**Solution**:
```bash
# Check pod status
kubectl get pods -n wikijs

# Check pod logs
kubectl logs -n wikijs -l app=wikijs

# Check service endpoints
kubectl get endpoints -n wikijs wikijs

# Verify health checks
kubectl describe pod -n wikijs <pod-name> | grep -A5 Readiness
```

## Wiki.js Application Issues

### Cannot Access Admin Panel

**Symptom**: Admin login fails or redirects

**Solution**:
1. Reset admin password via database:
```sql
psql -h <db-endpoint> -U wikijs -d wikijs

UPDATE users SET password = '$2a$12$...' WHERE email = 'admin@example.com';
```

2. Check Wiki.js logs:
```bash
kubectl logs -n wikijs -l app=wikijs --tail=100
```

### Wiki.js Shows Database Error

**Symptom**: "Database connection error" on startup

**Solution**:
```bash
# Verify database credentials
kubectl get secret -n wikijs wikijs-db-secret -o yaml

# Decode and verify each value
kubectl get secret -n wikijs wikijs-db-secret -o jsonpath='{.data.DB_HOST}' | base64 -d
kubectl get secret -n wikijs wikijs-db-secret -o jsonpath='{.data.DB_USER}' | base64 -d
kubectl get secret -n wikijs wikijs-db-secret -o jsonpath='{.data.DB_NAME}' | base64 -d

# Test database connection
kubectl run -it --rm psql-test --image=postgres:15 --restart=Never -n wikijs -- \
  psql -h <db-host> -U <db-user> -d <db-name> -c "SELECT version();"
```

### Pages Not Loading

**Symptom**: Wiki.js loads but pages fail

**Solution**:
```bash
# Check pod logs
kubectl logs -n wikijs -l app=wikijs --tail=50

# Check pod resources
kubectl top pods -n wikijs

# Increase resources if needed
kubectl edit deployment wikijs -n wikijs
# Update resources.limits.memory and resources.requests.memory
```

### Search Not Working

**Symptom**: Search returns no results

**Solution**:
1. Rebuild search index via Admin UI
2. Or via database:
```sql
-- Force search index rebuild
UPDATE settings SET value = 'true' WHERE key = 'search.rebuildOnStart';
```
3. Restart Wiki.js:
```bash
kubectl rollout restart deployment/wikijs -n wikijs
```

## Performance Issues

### High CPU Usage

**Symptom**: Node or pod CPU usage is high

**Solution**:
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n wikijs

# Scale horizontally
kubectl scale deployment/wikijs --replicas=2 -n wikijs

# Scale vertically (increase node size)
# Edit variables.tf: node_instance_type = "t3.medium"
terraform apply

# Enable autoscaling
kubectl autoscale deployment wikijs -n wikijs --cpu-percent=70 --min=1 --max=3
```

### High Memory Usage

**Symptom**: Pod or node memory usage is high

**Solution**:
```bash
# Check memory usage
kubectl top pods -n wikijs

# Increase pod memory limits
kubectl edit deployment wikijs -n wikijs
# Update resources.limits.memory to "2Gi"

# Or scale up node size
# Edit variables.tf: node_instance_type = "t3.medium"
terraform apply
```

### Slow Database Queries

**Symptom**: Wiki.js pages load slowly

**Solution**:
```sql
-- Connect to database
psql -h <db-endpoint> -U wikijs -d wikijs

-- Enable query logging
ALTER SYSTEM SET log_min_duration_statement = 1000;
SELECT pg_reload_conf();

-- View slow queries
SELECT query, calls, mean_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Add indexes if needed
CREATE INDEX idx_pages_path ON pages(path);
```

## Diagnostic Commands

### Comprehensive Health Check

```bash
#!/bin/bash
# health-check.sh

echo "=== Cluster Status ==="
kubectl cluster-info

echo -e "\n=== Nodes ==="
kubectl get nodes -o wide

echo -e "\n=== Pods ==="
kubectl get pods -n wikijs -o wide

echo -e "\n=== Services ==="
kubectl get svc -n wikijs

echo -e "\n=== Recent Events ==="
kubectl get events -n wikijs --sort-by='.lastTimestamp' | tail -20

echo -e "\n=== Pod Logs ==="
kubectl logs -n wikijs -l app=wikijs --tail=20

echo -e "\n=== Database Status ==="
aws rds describe-db-instances \
  --db-instance-identifier wikijs-cluster-db \
  --query 'DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' \
  --output table

echo -e "\n=== Resource Usage ==="
kubectl top nodes
kubectl top pods -n wikijs
```

### Collect Logs for Support

```bash
#!/bin/bash
# collect-logs.sh

mkdir -p wikijs-logs

# Cluster info
kubectl cluster-info > wikijs-logs/cluster-info.txt

# Pod status
kubectl get pods -n wikijs -o wide > wikijs-logs/pods.txt

# Pod logs
kubectl logs -n wikijs -l app=wikijs > wikijs-logs/wikijs-logs.txt

# Events
kubectl get events -n wikijs --sort-by='.lastTimestamp' > wikijs-logs/events.txt

# Terraform state
terraform show > wikijs-logs/terraform-state.txt

# Create archive
tar -czf wikijs-logs.tar.gz wikijs-logs/

echo "Logs collected in wikijs-logs.tar.gz"
```

## Getting Help

If you're still experiencing issues:

1. **Check Documentation**:
   - [DEPLOYMENT.md](./DEPLOYMENT.md)
   - [ARCHITECTURE.md](./ARCHITECTURE.md)

2. **Search Existing Issues**:
   - [GitHub Issues](https://github.com/Lodge104/docs.lodge104.net/issues)

3. **Create New Issue**:
   - Include output from health-check.sh
   - Attach wikijs-logs.tar.gz
   - Describe expected vs actual behavior

4. **Community Resources**:
   - [Wiki.js Discussions](https://github.com/requarks/wiki/discussions)
   - [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
   - [Kubernetes Slack](https://kubernetes.slack.com/)

## Prevention

### Pre-deployment Checklist

- [ ] AWS credentials configured
- [ ] Required AWS quotas available
- [ ] Terraform and kubectl installed
- [ ] terraform.tfvars properly configured
- [ ] Strong database password set

### Post-deployment Checklist

- [ ] All pods running
- [ ] LoadBalancer provisioned
- [ ] Database accessible
- [ ] Wiki.js setup completed
- [ ] Backups configured
- [ ] Monitoring enabled
- [ ] Documentation reviewed

### Maintenance Tasks

- [ ] Weekly: Check pod status and logs
- [ ] Weekly: Review resource usage
- [ ] Monthly: Update Wiki.js version
- [ ] Monthly: Review costs
- [ ] Quarterly: Update Terraform providers
- [ ] Quarterly: Review security settings

---

**Still stuck?** Create an issue with full details and logs!
