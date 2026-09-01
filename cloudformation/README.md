# CloudFormation Setup for GitHub OIDC Roles

## Purpose

This folder contains CloudFormation templates for AWS resources that must be created **before** running any Terraform workflows. These resources are required to avoid circular dependencies where Terraform would need to create roles that it itself needs to assume.

## Critical: Must Be Deployed First

⚠️ **These CloudFormation stacks must be deployed BEFORE any GitHub Actions workflow runs.**

## Deployment Steps

### 1. Create GitHub OIDC Provider (if not exists)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Deploy GitHub Roles

```bash
aws cloudformation deploy \
  --template-file github-oidc-roles.yaml \
  --stack-name github-oidc-roles \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides GitHubRepo=YOUR_ORG/YOUR_REPO
```

### 3. Get Role ARNs

```bash
aws cloudformation describe-stacks \
  --stack-name github-oidc-roles \
  --query 'Stacks[0].Outputs' \
  --output table
```

### 4. Set GitHub Repository Variables

Go to your GitHub repository Settings → Secrets and variables → Actions → Variables and add:

- `AWS_BOOTSTRAP_ROLE_ARN`: [From CloudFormation output BootstrapRoleArn]
- `AWS_ASSUME_ROLE_ARN`: [From CloudFormation output AssumeRoleArn]
- `AWS_REGION`: us-east-1 (or your preferred region)

## Role Architecture

### Bootstrap Role (`github-actions-bootstrap-role`)
- **Purpose**: Initial authentication via GitHub OIDC
- **Permissions**: Can only assume the target role
- **Trust**: GitHub Actions OIDC provider

### Target Role (`github-actions-assume-role`)
- **Purpose**: Full infrastructure deployment
- **Permissions**: AdministratorAccess (TODO: Scope down)
- **Trust**: Bootstrap role only

## Security Notes

1. The bootstrap role has minimal permissions (only sts:AssumeRole)
2. The target role should be scoped down to specific infrastructure permissions
3. Role chaining ensures temporary credentials with 1-hour session duration
4. GitHub OIDC trust is restricted to main branch only

## Cleanup

To remove all resources:

```bash
aws cloudformation delete-stack --stack-name github-oidc-roles
```