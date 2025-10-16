# Architecture Documentation

## Overview

This document describes the architecture of the Wiki.js deployment on AWS EKS.

## High-Level Architecture

```
                                    ┌─────────────────────────────────────────┐
                                    │          AWS Cloud (Region)             │
                                    │                                         │
┌──────────┐                       │  ┌───────────────────────────────────┐  │
│  Users   │────Internet────────────▶│  │  Application Load Balancer       │  │
│          │                       │  │  (Created by K8s Service)          │  │
└──────────┘                       │  └────────────────┬──────────────────┘  │
                                    │                   │                      │
                                    │  ┌────────────────▼──────────────────┐  │
                                    │  │         VPC (10.0.0.0/16)         │  │
                                    │  │                                    │  │
                                    │  │  ┌─────────────────────────────┐  │  │
                                    │  │  │  Public Subnet (10.0.0.0/24) │  │  │
                                    │  │  │  ┌──────────────────────┐   │  │  │
                                    │  │  │  │  NAT Gateway         │   │  │  │
                                    │  │  │  └──────────────────────┘   │  │  │
                                    │  │  │  ┌──────────────────────┐   │  │  │
                                    │  │  │  │  Internet Gateway    │   │  │  │
                                    │  │  │  └──────────────────────┘   │  │  │
                                    │  │  └─────────────────────────────┘  │  │
                                    │  │                                    │  │
                                    │  │  ┌─────────────────────────────┐  │  │
                                    │  │  │ Private Subnet (10.0.2.0/24) │  │  │
                                    │  │  │                              │  │  │
                                    │  │  │  ┌────────────────────────┐ │  │  │
                                    │  │  │  │  EKS Cluster           │ │  │  │
                                    │  │  │  │                        │ │  │  │
                                    │  │  │  │  ┌──────────────────┐ │ │  │  │
                                    │  │  │  │  │  Worker Node     │ │ │  │  │
                                    │  │  │  │  │  (t3.small)      │ │ │  │  │
                                    │  │  │  │  │                  │ │ │  │  │
                                    │  │  │  │  │  ┌────────────┐ │ │ │  │  │
                                    │  │  │  │  │  │ Wiki.js Pod│ │ │ │  │  │
                                    │  │  │  │  │  └────────────┘ │ │ │  │  │
                                    │  │  │  │  └──────────────────┘ │ │  │  │
                                    │  │  │  └────────────────────────┘ │  │  │
                                    │  │  │                              │  │  │
                                    │  │  │  ┌────────────────────────┐ │  │  │
                                    │  │  │  │  RDS PostgreSQL        │ │  │  │
                                    │  │  │  │  (db.t3.micro)         │ │  │  │
                                    │  │  │  └────────────────────────┘ │  │  │
                                    │  │  └─────────────────────────────┘  │  │
                                    │  └────────────────────────────────────┘  │
                                    └─────────────────────────────────────────┘
```

## Component Details

### 1. Networking Layer

#### VPC
- **CIDR Block**: 10.0.0.0/16
- **DNS Support**: Enabled
- **DNS Hostnames**: Enabled

#### Subnets
- **Public Subnets**: 2 subnets across 2 AZs (10.0.0.0/24, 10.0.1.0/24)
  - Used for: NAT Gateway, Load Balancers
  - Internet access: Via Internet Gateway
  
- **Private Subnets**: 2 subnets across 2 AZs (10.0.2.0/24, 10.0.3.0/24)
  - Used for: EKS nodes, RDS database
  - Internet access: Via NAT Gateway

#### Internet Gateway
- Provides internet access to public subnets
- Attached to VPC

#### NAT Gateway
- Located in public subnet
- Provides outbound internet access for private subnets
- Single gateway (cost optimization)

#### Route Tables
- **Public Route Table**
  - Default route (0.0.0.0/0) → Internet Gateway
  - Associated with public subnets

- **Private Route Table**
  - Default route (0.0.0.0/0) → NAT Gateway
  - Associated with private subnets

### 2. Compute Layer

#### EKS Cluster
- **Version**: Latest stable (managed by AWS)
- **Control Plane**: Fully managed by AWS
- **Endpoint Access**:
  - Public endpoint: Enabled (for kubectl access)
  - Private endpoint: Enabled (for pod-to-API communication)

#### Node Group
- **Instance Type**: t3.small (2 vCPU, 2 GiB RAM)
- **Capacity**:
  - Desired: 1 node
  - Minimum: 1 node
  - Maximum: 2 nodes (for auto-scaling)
- **Subnet Placement**: Private subnets
- **AMI**: AWS EKS-optimized AMI (automatically managed)

#### IAM Roles
- **EKS Cluster Role**
  - Policies: AmazonEKSClusterPolicy, AmazonEKSVPCResourceController
  - Used by: EKS control plane

- **Node Role**
  - Policies: AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly
  - Used by: Worker nodes

### 3. Database Layer

#### RDS PostgreSQL
- **Engine**: PostgreSQL 15.4
- **Instance Class**: db.t3.micro (2 vCPU, 1 GiB RAM)
- **Storage**:
  - Type: GP2 (General Purpose SSD)
  - Size: 20 GB
  - Auto-scaling: Disabled (can be enabled)
- **Deployment**: Single-AZ (for cost optimization)
- **Backup**: Disabled (should be enabled for production)
- **Subnet Group**: Private subnets
- **Public Access**: Disabled

#### Database Security
- **Security Group**: Allows traffic only from EKS cluster security group
- **Port**: 5432 (PostgreSQL)
- **Encryption**: At rest (default AWS encryption)

### 4. Application Layer

#### Kubernetes Resources

##### Namespace: wikijs
Isolated namespace for Wiki.js resources

##### Secret: wikijs-db-secret
Contains database connection credentials:
- DB_TYPE: postgres
- DB_HOST: RDS endpoint
- DB_PORT: 5432
- DB_USER: wikijs
- DB_PASS: (from Terraform variable)
- DB_NAME: wikijs

##### Deployment: wikijs
- **Replicas**: 1
- **Container Image**: ghcr.io/requarks/wiki:2
- **Resources**:
  - Requests: 250m CPU, 512Mi memory
  - Limits: 500m CPU, 1Gi memory
- **Probes**:
  - Liveness: HTTP GET /healthz every 10s (after 30s delay)
  - Readiness: HTTP GET /healthz every 5s (after 10s delay)
- **Environment**: Database credentials from secret

##### Service: wikijs
- **Type**: LoadBalancer
- **Port Mapping**: 80 (external) → 3000 (container)
- **Protocol**: TCP
- **Load Balancer**: AWS Application Load Balancer (automatically created)

### 5. Security Layer

#### Security Groups

##### EKS Cluster Security Group
- **Ingress**: Managed by EKS
- **Egress**: All traffic allowed

##### RDS Security Group
- **Ingress**: 
  - Port 5432 from EKS cluster security group
- **Egress**: All traffic allowed

#### Network ACLs
- Default VPC NACLs (allow all traffic)

#### IAM Policies
- Principle of least privilege
- Separate roles for cluster and nodes
- No overly permissive policies

## Data Flow

### User Request Flow
1. User accesses Wiki.js via browser
2. DNS resolves to Application Load Balancer hostname
3. ALB forwards traffic to Kubernetes Service
4. Service routes to Wiki.js Pod on worker node
5. Pod processes request
6. If database access needed, Pod connects to RDS via private network
7. Response flows back through Service → ALB → User

### Database Connection Flow
1. Wiki.js Pod reads credentials from Kubernetes Secret
2. Establishes connection to RDS endpoint
3. Traffic stays within private subnet
4. Security group allows traffic from EKS to RDS
5. PostgreSQL processes query
6. Results returned to Pod

### External Access Flow
1. Worker node needs to pull container images
2. Traffic routes through NAT Gateway
3. NAT Gateway forwards to Internet Gateway
4. Node downloads image from ghcr.io
5. Connection established, image pulled

## High Availability Considerations

### Current Setup (Cost-Optimized)
- **Single Node**: If node fails, service is down until new node launches
- **Single AZ Database**: If AZ fails, database is unavailable
- **Single NAT Gateway**: If NAT fails, nodes lose internet access

### Improvements for Production
1. **Multiple Nodes**: 
   ```hcl
   desired_capacity = 2
   min_capacity     = 2
   ```

2. **Multi-AZ RDS**:
   ```hcl
   multi_az = true
   ```

3. **Multiple NAT Gateways**:
   ```hcl
   # Create NAT Gateway in each public subnet
   resource "aws_nat_gateway" "main" {
     count = 2
     # ...
   }
   ```

4. **Pod Disruption Budget**:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: wikijs-pdb
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: wikijs
   ```

## Scaling

### Horizontal Pod Autoscaling
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: wikijs-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: wikijs
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Cluster Autoscaling
```hcl
resource "aws_eks_node_group" "main" {
  # ...
  scaling_config {
    desired_size = 1
    max_size     = 5  # Allow scaling up to 5 nodes
    min_size     = 1
  }
}
```

## Monitoring and Observability

### CloudWatch Integration
- **EKS Control Plane Logs**: API server, audit, authenticator
- **Container Insights**: Node and pod metrics
- **RDS Monitoring**: CPU, memory, connections, IOPS

### Kubernetes Metrics
- **Metrics Server**: For HPA and resource usage
- **kubectl top**: View resource consumption

### Application Logs
- **Container Logs**: `kubectl logs -f deployment/wikijs -n wikijs`
- **CloudWatch Logs**: Via Fluentd/Fluent Bit

## Disaster Recovery

### Backup Strategy
1. **RDS Automated Backups**:
   ```hcl
   backup_retention_period = 7
   backup_window          = "03:00-04:00"
   ```

2. **RDS Snapshots**:
   ```bash
   aws rds create-db-snapshot \
     --db-instance-identifier wikijs-cluster-db \
     --db-snapshot-identifier manual-backup
   ```

3. **Wiki.js Configuration**:
   - Export via Admin UI
   - Store in S3 or Git

### Recovery Procedures
1. **Node Failure**: Auto Scaling Group launches new node
2. **Pod Failure**: Kubernetes restarts pod automatically
3. **Database Failure**: Restore from automated backup or snapshot
4. **Complete Disaster**: Run `terraform apply` with backed-up state

## Cost Optimization

See [COST_OPTIMIZATION.md](./COST_OPTIMIZATION.md) for detailed strategies.

### Current Monthly Cost Breakdown
```
EKS Control Plane:     $73.00
EC2 t3.small:          $15.00
RDS db.t3.micro:       $15.00
NAT Gateway:           $32.00
Storage & Transfer:     $5.00
─────────────────────────────
Total:               ~$140.00/month
```

## Security Best Practices

### Network Security
- ✅ Private subnets for compute and database
- ✅ Security groups with minimal access
- ✅ No public database access
- ⚠️ Consider: VPC Flow Logs for monitoring

### Application Security
- ✅ Secrets stored in Kubernetes Secrets (encrypted at rest)
- ✅ Container images from trusted registry
- ✅ Resource limits defined
- ⚠️ Consider: Pod Security Standards
- ⚠️ Consider: Network Policies

### Database Security
- ✅ Encryption at rest
- ✅ Private subnet deployment
- ✅ Security group restrictions
- ⚠️ Consider: Encryption in transit (SSL)
- ⚠️ Consider: IAM database authentication

### Access Control
- ✅ IAM roles with least privilege
- ✅ EKS API authentication
- ⚠️ Consider: RBAC for Kubernetes resources
- ⚠️ Consider: AWS Organizations for multi-account

## Performance Tuning

### Database Optimization
```sql
-- Increase connection limit if needed
ALTER SYSTEM SET max_connections = 100;

-- Enable query logging for slow queries
ALTER SYSTEM SET log_min_duration_statement = 1000;

-- Tune buffer sizes
ALTER SYSTEM SET shared_buffers = '256MB';
```

### Application Optimization
```yaml
# Increase resources if needed
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

### Network Optimization
- Enable VPC endpoints for AWS services (S3, ECR)
- Use AWS PrivateLink to avoid NAT Gateway costs

## Troubleshooting

### Common Issues

1. **Pod CrashLoopBackOff**
   - Check logs: `kubectl logs <pod> -n wikijs`
   - Check events: `kubectl describe pod <pod> -n wikijs`
   - Verify database connectivity

2. **LoadBalancer Not Created**
   - Check service: `kubectl describe svc wikijs -n wikijs`
   - Verify subnet tags: `kubernetes.io/role/elb`
   - Check AWS Load Balancer Controller logs

3. **Database Connection Timeout**
   - Verify security group rules
   - Check RDS status
   - Verify network connectivity from pod

## Future Enhancements

### Short-term
- [ ] Add HTTPS/TLS support
- [ ] Implement automated backups
- [ ] Add monitoring dashboards
- [ ] Set up alerting

### Medium-term
- [ ] Multi-AZ deployment
- [ ] Implement CI/CD pipeline
- [ ] Add staging environment
- [ ] Implement auto-scaling

### Long-term
- [ ] Multi-region deployment
- [ ] Disaster recovery automation
- [ ] Advanced monitoring (Prometheus/Grafana)
- [ ] Service mesh (Istio/Linkerd)

## References

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Wiki.js Documentation](https://docs.requarks.io/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
