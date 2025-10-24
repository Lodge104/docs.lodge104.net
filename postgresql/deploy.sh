#!/bin/bash

# Aurora Serverless v2 PostgreSQL Database Deployment Script
# This script deploys a cost-optimized Aurora Serverless v2 PostgreSQL database

set -e

echo "🚀 Deploying Aurora Serverless v2 PostgreSQL Database (Cost Optimized)"
echo "=================================================================="

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Navigate to the postgresql directory
cd "$(dirname "$0")"

# Copy example terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo "📋 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "✅ terraform.tfvars created. You can edit it to customize settings."
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📋 Planning deployment..."
terraform plan

# Ask for confirmation
echo ""
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying infrastructure..."
    terraform apply -auto-approve
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📝 Important Information:"
    echo "========================"
    echo "• Database password is stored in AWS Systems Manager Parameter Store"
    echo "• Retrieve password with: aws ssm get-parameter --name '/wiki/database/password' --with-decryption --query 'Parameter.Value' --output text"
    echo "• This configuration is optimized for cost with 0.5-1.0 ACU scaling"
    echo "• Estimated monthly cost: $6-25 depending on usage"
    echo ""
    echo "📊 Connection Details:"
    terraform output
else
    echo "❌ Deployment cancelled."
    exit 1
fi