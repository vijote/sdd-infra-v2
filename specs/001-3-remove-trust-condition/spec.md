# Spec: Remove Trust Condition from Assume Role

**Feature Branch**: `001-3-remove-trust-condition` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: AWS IAM Role / CloudFormation Template / Trust Policy
- **Kubernetes / Cluster Scope**: None (IAM infrastructure only)
- **Target Services / Modules**: CloudFormation assume-role.yaml template
- **Security & CI/CD**: GitHub Actions assume role without restrictive conditions

### 1.1 CloudFormation / IAM Resource Contracts
```yaml
# Assume Role Policy Document without Conditions
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        AWS: !Ref BootstrapRoleArn
      Action:
        - sts:AssumeRole
        - sts:TagSession
```

### 1.2 IAM Permission Contracts
- **sts:AssumeRole**: Permission for role assumption
- **sts:TagSession**: Permission for session tagging during role assumption
- **Bootstrap Role ARN**: Trusted principal that can assume the role
- **No Conditions**: Trust relationship without StringEquals conditions

### 1.3 Security Impact Contracts
- **Principal-Based Trust**: Only BootstrapRoleArn can assume the role
- **No ExternalId**: Removes ExternalId condition that was blocking role chaining
- **No PrincipalArn Condition**: Removes redundant PrincipalArn validation
- **Session Tagging**: Enables GitHub Actions to pass session tags

## 2. Assumptions & Technical Constraints
- **Existing Role**: assume-role.yaml CloudFormation template exists in cloudformation/ directory
- **Bootstrap Role**: Bootstrap role ARN is provided as parameter
- **Role Name**: github-actions-assume-role (existing)
- **Permissions**: Existing PowerUserAccess and TerraformStateAccess policies remain unchanged
- **Constitution Compliance**: No validation, testing, or verification steps in implementation