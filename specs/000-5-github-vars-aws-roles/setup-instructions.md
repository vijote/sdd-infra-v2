# GitHub Repository Variables Setup Guide

This guide provides step-by-step instructions for setting up the required GitHub repository variables for the AWS role chaining authentication system.

## Prerequisites

- AWS IAM roles must be deployed via CloudFormation stack `cloudformation/github-oidc-roles.yaml`
- GitHub repository administrator access
- AWS account with CloudFormation outputs available

## CloudFormation Deployment

Before setting up repository variables, deploy the CloudFormation stack:

```bash
aws cloudformation deploy \
  --template-file cloudformation/github-oidc-roles.yaml \
  --stack-name github-oidc-roles \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=vijote \
    GitHubRepo=sdd-infra-v2
```

Get the CloudFormation outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name github-oidc-roles \
  --query 'Stacks[0].Outputs' \
  --output table
```

## Repository Variables Configuration

### 1. AWS_BOOTSTRAP_ROLE_ARN

**Purpose**: ARN of the bootstrap role with minimal sts:AssumeRole permissions

**How to set**:
1. Navigate to GitHub repository: `https://github.com/vijote/sdd-infra-v2`
2. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
3. Click **New repository variable**
4. Name: `AWS_BOOTSTRAP_ROLE_ARN`
5. Value: `<BootstrapRoleArn>` from CloudFormation outputs
6. Click **Add variable**

**Example value**: `arn:aws:iam::123456789012:role/github-actions-bootstrap-role`

### 2. AWS_ASSUME_ROLE_ARN

**Purpose**: ARN of the assume role with full infrastructure deployment permissions

**How to set**:
1. Navigate to GitHub repository: `https://github.com/vijote/sdd-infra-v2`
2. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
3. Click **New repository variable**
4. Name: `AWS_ASSUME_ROLE_ARN`
5. Value: `<AssumeRoleArn>` from CloudFormation outputs
6. Click **Add variable**

**Example value**: `arn:aws:iam::123456789012:role/github-actions-assume-role`

### 3. AWS_REGION

**Purpose**: AWS region for infrastructure deployment

**How to set**:
1. Navigate to GitHub repository: `https://github.com/vijote/sdd-infra-v2`
2. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
3. Click **New repository variable**
4. Name: `AWS_REGION`
5. Value: `us-east-1` (or your preferred region)
6. Click **Add variable**

**Example value**: `us-east-1`

## Verification

After setting up all repository variables, verify the configuration:

1. Navigate to **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Confirm all three variables are present:
   - `AWS_BOOTSTRAP_ROLE_ARN`
   - `AWS_ASSUME_ROLE_ARN`
   - `AWS_REGION`
3. Ensure values match CloudFormation outputs

## CloudFormation Output Values Reference

After deploying the CloudFormation stack, use these values for repository variables:

```bash
# Get bootstrap role ARN
aws cloudformation describe-stacks \
  --stack-name github-oidc-roles \
  --query 'Stacks[0].Outputs[?OutputKey==`BootstrapRoleArn`].OutputValue' \
  --output text

# Get assume role ARN
aws cloudformation describe-stacks \
  --stack-name github-oidc-roles \
  --query 'Stacks[0].Outputs[?OutputKey==`AssumeRoleArn`].OutputValue' \
  --output text
```

## Troubleshooting

### Issues with CloudFormation Deployment

- Ensure AWS CLI is configured with appropriate permissions
- Check that the OIDC provider exists: `aws iam list-open-id-connect-providers`
- Verify stack parameters match your GitHub organization and repository

### Issues with GitHub Variables

- Ensure you have repository administrator permissions
- Check that variable names are exactly as specified (case-sensitive)
- Verify ARNs are complete and valid format

### Role Chain Testing

After configuration, test the role chain manually:

```bash
# Set repository variables as environment variables
export AWS_BOOTSTRAP_ROLE_ARN="arn:aws:iam::123456789012:role/github-actions-bootstrap-role"
export AWS_ASSUME_ROLE_ARN="arn:aws:iam::123456789012:role/github-actions-assume-role"
export AWS_REGION="us-east-1"

# Test bootstrap role assumption (requires GitHub Actions OIDC token)
# This will only work within GitHub Actions environment
aws sts get-caller-identity
```

## Next Steps

After completing repository variable setup:

1. GitHub Actions workflows will automatically use these variables
2. Role chaining will be configured in workflow files
3. Infrastructure deployment can proceed with secure credential management

## Security Considerations

- Bootstrap role has minimal permissions (sts:AssumeRole only)
- Assume role has scoped infrastructure permissions
- Temporary credentials via role chaining (1-hour session duration)
- No hardcoded credentials in workflow files
- All configuration managed via GitHub repository variables