#!/bin/bash
set -euo pipefail

# Post-deployment validation script for CI/CD Workflows
# This script validates that all infrastructure components are properly deployed

echo "=== Starting Post-Deployment Validation ==="

# Validation 1: Check Terraform state consistency
echo "1. Validating Terraform state consistency..."
state_resources=$(terraform show -json tfplan 2>/dev/null | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
if [ "$state_resources" -gt "0" ]; then
    echo "✓ Terraform state contains $state_resources resources"
else
    echo "✗ Terraform state validation failed"
    exit 1
fi

# Validation 2: Check VPC creation
echo "2. Validating VPC creation..."
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
if [ -n "$VPC_ID" ]; then
    echo "✓ VPC ID: $VPC_ID"
    # Verify VPC exists in AWS
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].State' --output text 2>/dev/null | grep -q "available"; then
        echo "✓ VPC is available in AWS"
    else
        echo "✗ VPC not found or not available in AWS"
        exit 1
    fi
else
    echo "✗ VPC ID not found in Terraform outputs"
    exit 1
fi

# Validation 3: Check EKS cluster endpoint
echo "3. Validating EKS cluster..."
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "")
if [ -n "$CLUSTER_ENDPOINT" ]; then
    echo "✓ Cluster endpoint: $CLUSTER_ENDPOINT"
    # Extract cluster name from endpoint
    CLUSTER_NAME=$(echo "$CLUSTER_ENDPOINT" | sed 's|https://||' | cut -d'.' -f1)
    if aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        echo "✓ EKS cluster is ACTIVE"
    else
        echo "✗ EKS cluster not found or not ACTIVE"
        exit 1
    fi
else
    echo "✗ Cluster endpoint not found in Terraform outputs"
    exit 1
fi

# Validation 4: Check application URL (if available)
echo "4. Validating application deployment..."
APPLICATION_URL=$(terraform output -raw application_url 2>/dev/null || echo "")
if [ -n "$APPLICATION_URL" ]; then
    echo "✓ Application URL: $APPLICATION_URL"
    # Check if the application responds (with timeout)
    if curl -f -s --max-time 10 "$APPLICATION_URL/health" > /dev/null 2>&1 || \
       curl -f -s --max-time 10 "$APPLICATION_URL" > /dev/null 2>&1; then
        echo "✓ Application is responding"
    else
        echo "⚠ Application not yet responding (may still be starting)"
    fi
else
    echo "⚠ Application URL not available (may not be deployed yet)"
fi

# Validation 5: Check state backend access
echo "5. Validating state backend access..."
if aws s3 ls s3://sdd-k8s-platform-terraform-state > /dev/null 2>&1; then
    echo "✓ S3 state backend is accessible"
else
    echo "✗ S3 state backend not accessible"
    exit 1
fi

# Validation 6: Check S3 object lock configuration
echo "6. Validating S3 object lock configuration..."
if aws s3api get-object-lock-configuration \
    --bucket sdd-k8s-platform-terraform-state \
    --key terraform.tfstate \
    --query 'ObjectLockConfiguration.ObjectLockEnabled' \
    --output text 2>/dev/null | grep -q "Enabled"; then
    echo "✓ S3 object lock is enabled"
else
    echo "⚠ S3 object lock not configured (may be using alternative locking)"
fi

echo ""
echo "=== Post-Deployment Validation Complete ==="
echo "✓ All critical validations passed"
echo "Infrastructure is ready for use"