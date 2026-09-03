# Spec: CloudFormation Circular Dependency Fix

**Feature Branch**: `000-8-cloudformation-circular-dependency-fix` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: CloudFormation IAM Roles / AWS OIDC Authentication / Role Chaining Architecture
- **Kubernetes / Cluster Scope**: N/A (CloudFormation-only fix)
- **Target Services / Modules**: `cloudformation/github-oidc-roles.yaml` template
- **Security & CI/CD**: GitHub OIDC trust relationship, role chaining security model

### 1.1 CloudFormation Resource Contracts
```yaml
# Bootstrap Role - OIDC Trust with Assume Role Reference
BootstrapRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: github-actions-bootstrap-role
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Federated: !Sub arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com
          Action: sts:AssumeRoleWithWebIdentity
          Condition:
            StringEquals:
              token.actions.githubusercontent.com:aud: sts.amazonaws.com
            StringLike:
              token.actions.githubusercontent.com:sub: !Sub repo:${GitHubOrg}/${GitHubRepo}:*
    Policies:
      - PolicyName: BootstrapAssumeRolePolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            - Effect: Allow
              Action: sts:AssumeRole
              Resource: !Ref AssumeRole  # Use !Ref instead of !GetAtt to avoid circular dependency

# Assume Role - Chaining Trust with Bootstrap Role Reference
AssumeRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: github-actions-assume-role
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            AWS: !Ref BootstrapRole  # Use !Ref instead of !GetAtt to avoid circular dependency
          Action: sts:AssumeRole
          Condition:
            StringEquals:
              aws:PrincipalArn: !Ref BootstrapRole
              sts:ExternalId: !Ref AssumeRole
```

### 1.2 Data & Storage Contracts
- **Repository Variables**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION
- **Role Session Duration**: 3600 seconds (1 hour) for GitHub Actions workflow
- **External ID Pattern**: Role ARN used as external ID for security boundary enforcement

### 1.3 Network & Security Contracts
- **Bootstrap Role**: OIDC trust with GitHub Actions, minimal permissions (sts:AssumeRole only)
- **Assume Role**: Infrastructure deployment permissions, accepts chained role assumption
- **External ID Validation**: Uses assume role reference as external ID for cross-account security
- **Circular Dependency Resolution**: !Ref instead of !GetAtt eliminates circular dependency

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: CloudFormation template validates without circular dependency errors (`aws cloudformation validate-template --template-body file://cloudformation/github-oidc-roles.yaml`)
- [ ] AC-002: No !GetAtt references between BootstrapRole and AssumeRole (`! grep -A 2 "Resource:" cloudformation/github-oidc-roles.yaml | grep -v "GetAtt"`)
- [ ] AC-003: BootstrapRole uses !Ref AssumeRole in policy (`grep -q "Resource: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml`)
- [ ] AC-004: AssumeRole uses !Ref BootstrapRole in trust policy (`grep -q "AWS: !Ref BootstrapRole" cloudformation/github-oidc-roles.yaml`)
- [ ] AC-005: External ID condition uses !Ref AssumeRole (`grep -q "sts:ExternalId: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml`)
- [ ] AC-006: CloudFormation stack deploys successfully (`aws cloudformation deploy --stack-name github-oidc-roles --template-file cloudformation/github-oidc-roles.yaml --capabilities CAPABILITY_NAMED_IAM`)
- [ ] AC-007: Role ARNs are properly exported (`aws cloudformation describe-stacks --stack-name github-oidc-roles --query "Stacks[0].Outputs" | grep -E "BootstrapRoleArn|AssumeRoleArn"`)

## 3. Assumptions & Technical Constraints
- **CloudFormation Stack**: Existing github-oidc-roles stack may need to be recreated due to resource changes
- **Repository Variables**: GitHub repository variables must be reconfigured with new role ARNs after deployment
- **GitHub Actions Version**: aws-actions/configure-aws-credentials@v4 or higher with role-chaining support
- **AWS Permissions**: Assume role must include sts:ExternalId condition for security boundary enforcement
- **Circular Dependency Resolution**: !Ref instead of !GetAtt eliminates circular dependency while maintaining same functionality
- **Backward Compatibility**: Role names remain unchanged (github-actions-bootstrap-role, github-actions-assume-role)
- **Testing Policy**: No unit or E2E test generation - validation performed via CloudFormation deployment and AWS CLI verification
- **Security Model**: Bootstrap role → Assume role with external ID validation maintained, only reference method changed