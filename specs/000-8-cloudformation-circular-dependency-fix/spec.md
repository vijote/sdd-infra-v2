# Spec: CloudFormation Circular Dependency Fix

**Feature Branch**: `000-8-cloudformation-circular-dependency-fix` | **Date**: 2026-09-02 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: CloudFormation IAM Roles / AWS OIDC Authentication / Role Chaining Architecture
- **Kubernetes / Cluster Scope**: N/A (CloudFormation-only fix)
- **Target Services / Modules**: Two separate CloudFormation stacks for sequential deployment
- **Security & CI/CD**: GitHub OIDC trust relationship, role chaining security model

### 1.1 CloudFormation Resource Contracts
```yaml
# Stack 1: Bootstrap Role (No Dependencies)
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
              Resource: !Sub arn:aws:iam::${AWS::AccountId}:role/github-actions-assume-role

# Stack 2: Assume Role (Parameter-Based Bootstrap Reference)
Parameters:
  BootstrapRoleArn:
    Type: String
    Description: ARN of the bootstrap role from Stack 1

AssumeRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: github-actions-assume-role
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            AWS: !Ref BootstrapRoleArn
          Action: sts:AssumeRole
          Condition:
            StringEquals:
              aws:PrincipalArn: !Ref BootstrapRoleArn
              sts:ExternalId: !Sub ${AWS::AccountId}
```

### 1.2 Data & Storage Contracts
- **Repository Variables**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION
- **Role Session Duration**: 3600 seconds (1 hour) for GitHub Actions workflow
- **External ID Pattern**: AWS account ID used as external ID for security boundary enforcement
- **Stack Parameters**: BootstrapRoleArn passed as parameter to AssumeRole stack

### 1.3 Network & Security Contracts
- **Bootstrap Role**: OIDC trust with GitHub Actions, minimal permissions (sts:AssumeRole only)
- **Assume Role**: Infrastructure deployment permissions, accepts parameter-based BootstrapRoleArn
- **External ID Validation**: Uses AWS account ID as external ID for cross-account security
- **Circular Dependency Resolution**: Two separate stacks with parameter-based references eliminate circular dependency

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Bootstrap stack validates without errors (`aws cloudformation validate-template --template-body file://cloudformation/bootstrap-role.yaml`)
- [ ] AC-002: Assume stack validates without errors (`aws cloudformation validate-template --template-body file://cloudformation/assume-role.yaml`)
- [ ] AC-003: Bootstrap stack deploys successfully (`aws cloudformation deploy --stack-name github-oidc-bootstrap-role --template-file cloudformation/bootstrap-role.yaml --capabilities CAPABILITY_NAMED_IAM`)
- [ ] AC-004: Bootstrap stack outputs BootstrapRoleArn (`aws cloudformation describe-stacks --stack-name github-oidc-bootstrap-role --query "Stacks[0].Outputs[?OutputKey=='BootstrapRoleArn'].OutputValue" --output text`)
- [ ] AC-005: Assume stack deploys with BootstrapRoleArn parameter (`aws cloudformation deploy --stack-name github-oidc-assume-role --template-file cloudformation/assume-role.yaml --parameter-overrides BootstrapRoleArn=<ARN> --capabilities CAPABILITY_NAMED_IAM`)
- [ ] AC-006: Assume stack outputs AssumeRoleArn (`aws cloudformation describe-stacks --stack-name github-oidc-assume-role --query "Stacks[0].Outputs[?OutputKey=='AssumeRoleArn'].OutputValue" --output text`)
- [ ] AC-007: Both role ARNs are properly exported and accessible for GitHub Actions configuration

## 3. Assumptions & Technical Constraints
- **Sequential Deployment**: Bootstrap stack must be deployed before Assume stack
- **Parameter Passing**: BootstrapRoleArn extracted from Stack 1 outputs and passed to Stack 2
- **Repository Variables**: GitHub repository variables must be configured with both role ARNs after deployment
- **GitHub Actions Version**: aws-actions/configure-aws-credentials@v4 or higher with role-chaining support
- **AWS Permissions**: Assume role must include sts:ExternalId condition for security boundary enforcement
- **Circular Dependency Resolution**: Two-stack approach with parameter-based references eliminates circular dependency
- **Backward Compatibility**: Role names remain unchanged (github-actions-bootstrap-role, github-actions-assume-role)
- **Testing Policy**: No unit or E2E test generation - validation performed via CloudFormation deployment and AWS CLI verification
- **Security Model**: Bootstrap role → Assume role with external ID validation maintained, deployment approach changed