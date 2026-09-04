# Spec: STS TagSession Role Enhancement

**Feature Branch**: `001-2-sts-tagsession-role` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: AWS IAM Role / CloudFormation Template / STS Permissions
- **Kubernetes / Cluster Scope**: None (IAM infrastructure only)
- **Target Services / Modules**: CloudFormation assume-role.yaml template
- **Security & CI/CD**: GitHub Actions assume role with session tagging capability

### 1.1 CloudFormation / IAM Resource Contracts
```yaml
# Assume Role Policy Document with TagSession
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        AWS: !Ref BootstrapRoleArn
      Action:
        - sts:AssumeRole
        - sts:TagSession
      Condition:
        StringEquals:
          aws:PrincipalArn: !Ref BootstrapRoleArn
          sts:ExternalId: !Ref AWS::AccountId
```

### 1.2 IAM Permission Contracts
- **sts:AssumeRole**: Existing permission for role assumption
- **sts:TagSession**: New permission for session tagging during role assumption
- **Bootstrap Role ARN**: Trusted principal that can assume the role
- **External ID Condition**: Additional security constraint for role assumption

### 1.3 Session Tagging Contracts
- **Tag Key-Value Pairs**: GitHub Actions can pass session tags during role assumption
- **Tag Propagation**: Tags can be propagated to downstream AWS resources
- **Audit Trail**: Session tags provide better tracking and attribution

## 2. Assumptions & Technical Constraints
- **Existing Role**: assume-role.yaml CloudFormation template exists in cloudformation/ directory
- **Bootstrap Role**: Bootstrap role ARN is provided as parameter
- **Role Name**: github-actions-assume-role (existing)
- **Permissions**: Existing PowerUserAccess and TerraformStateAccess policies remain unchanged
- **Constitution Compliance**: No validation, testing, or verification steps in implementation