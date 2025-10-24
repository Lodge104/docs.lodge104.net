#!/bin/bash

# Aurora Serverless v2 PostgreSQL Database Cleanup Script
# This script destroys all resources to stop incurring costs

set -e

echo "🗑️  Aurora Serverless v2 PostgreSQL Database Cleanup"
echo "=================================================="

# Navigate to the postgresql directory
cd "$(dirname "$0")"

# Check if Terraform is initialized
if [ ! -f ".terraform.lock.hcl" ]; then
    echo "❌ Terraform not initialized. Nothing to destroy."
    exit 1
fi

echo "⚠️  WARNING: This will destroy all Aurora database resources!"
echo "This action cannot be undone and will result in data loss."
echo ""
echo "Resources to be destroyed:"
echo "• Aurora Serverless v2 cluster 'wiki-aurora-cluster'"
echo "• Aurora instance 'wiki-aurora-instance'"
echo "• Database security group"
echo "• Database subnet group"
echo "• Systems Manager parameter (password)"
echo ""

read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
echo ""

if [[ $REPLY == "yes" ]]; then
    echo "🔍 Planning destruction..."
    terraform plan -destroy
    
    echo ""
    read -p "Final confirmation - destroy all resources? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Destroying infrastructure..."
        terraform destroy -auto-approve
        
        echo ""
        echo "✅ All resources have been destroyed successfully!"
        echo "💰 You are no longer incurring costs for these resources."
    else
        echo "❌ Destruction cancelled."
        exit 1
    fi
else
    echo "❌ Destruction cancelled. You must type 'yes' exactly to confirm."
    exit 1
fi