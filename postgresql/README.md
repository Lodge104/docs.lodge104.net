# Aurora Serverless v2 PostgreSQL Database - Cost Optimized

This Terraform configuration creates an AWS Aurora Serverless v2 PostgreSQL database named "wiki" with maximum cost optimization.

## Cost Optimization Features

- **Minimum ACU Configuration**: 0.5-1.0 ACUs (Aurora Capacity Units)
- **Auto-scaling**: Automatically scales down to zero when not in use
- **Single Instance**: No read replicas to minimize costs
- **Minimal Backup**: 1-day backup retention (minimum allowed)
- **Default VPC**: Uses existing default VPC to avoid networking costs
- **No Encryption**: Storage encryption disabled to reduce costs
- **No Enhanced Monitoring**: Monitoring disabled to avoid extra charges
- **No Performance Insights**: Disabled to save costs

## Estimated Costs

- **Minimum**: ~$6-10/month when database is mostly idle
- **Maximum**: ~$15-25/month under light usage
- **Aurora Serverless v2**: $0.50 per ACU per hour (only when active)
- **Storage**: $0.10 per GB per month for data storage
- **Backup**: $0.021 per GB per month for backup storage (1 day retention)

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. An AWS account with necessary permissions
4. **VPC Peering enabled for Lightsail** in your AWS region (for Lightsail container access)
   - See: [VPC Peering Setup Guide](https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-how-to-set-up-vpc-peering-with-aws-resources.html)

## Deployment Instructions

1. **Clone and navigate to the postgresql directory**:
   ```bash
   cd postgresql
   ```

2. **Copy the example variables file**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit terraform.tfvars** (optional - defaults are already cost-optimized):
   ```bash
   nano terraform.tfvars
   ```

4. **Initialize Terraform**:
   ```bash
   terraform init
   ```

5. **Plan the deployment**:
   ```bash
   terraform plan
   ```

6. **Apply the configuration**:
   ```bash
   terraform apply
   ```

## Accessing the Database

After deployment, you'll get:
- **Endpoint**: Cluster endpoint URL
- **Port**: 5432 (PostgreSQL default)
- **Database**: wiki
- **Username**: postgres (default)
- **Password**: Stored in AWS Systems Manager Parameter Store

### Retrieving the Password

```bash
aws ssm get-parameter --name "/wiki/database/password" --with-decryption --query 'Parameter.Value' --output text
```

### Connecting to the Database

```bash
# Using psql
psql -h <cluster-endpoint> -U postgres -d wiki

# Connection string format
postgresql://postgres:<password>@<cluster-endpoint>:5432/wiki
```

## Security Considerations

- Database is accessible within the VPC only (not publicly accessible)
- Password is stored securely in AWS Systems Manager
- Security group restricts access to VPC CIDR block and Lightsail CIDR (via VPC Peering)
- VPC Peering provides secure connectivity without exposing database to internet

## Amazon Lightsail Container Services Integration

With VPC Peering enabled, your Lightsail container services can securely connect to the Aurora database:

1. **Automatic Setup**: VPC Peering allows Lightsail containers to access your default VPC
2. **Secure Connection**: No public internet exposure required
3. **Cost Effective**: No additional NAT Gateway or data transfer charges
4. **Low Latency**: Direct connection between Lightsail and your VPC

### Connecting from Lightsail Containers

Use the cluster endpoint directly in your Lightsail container applications:

```bash
# Environment variables for your Lightsail container
DB_HOST=<cluster-endpoint>
DB_PORT=5432
DB_NAME=wiki
DB_USER=postgres
DB_PASSWORD=<retrieved-from-ssm>
```

## Additional Cost Savings Tips

1. **Monitor Usage**: Use AWS Cost Explorer to track actual costs
2. **Set Billing Alerts**: Create CloudWatch billing alarms
3. **Scale Settings**: Adjust min/max capacity based on actual usage
4. **Unused Resources**: Remember to `terraform destroy` when not needed
5. **Regional Costs**: us-east-1 is typically the cheapest AWS region

## Cleanup

To destroy all resources and stop incurring costs:

```bash
terraform destroy
```

## Troubleshooting

- **Permission Issues**: Ensure your AWS credentials have RDS and VPC permissions
- **Region Issues**: Verify the AWS region supports Aurora Serverless v2
- **VPC Issues**: If default VPC doesn't exist, create one or modify the configuration

## File Structure

```
postgresql/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars.example   # Example variables file
└── README.md                  # This file
```