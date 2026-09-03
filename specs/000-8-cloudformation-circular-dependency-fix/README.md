# CloudFormation Circular Dependency Fix

## Overview
This spec resolves a circular dependency issue in the GitHub Actions OIDC role configuration by implementing a two-stack sequential deployment approach.

## Problem Statement

### Original Issue
The CloudFormation template `github-oidc-roles.yaml` contained a circular dependency:
- **BootstrapRole** referenced **AssumeRole** in its policy (Resource field)
- **AssumeRole** referenced **BootstrapRole** in its trust policy (Principal field)

### Why It Failed
CloudFormation cannot resolve mutual resource dependencies, regardless of whether `!GetAtt` or `!Ref` is used. Both create resource references that form a dependency cycle.

### Error Message
```
Circular dependency between resources: [BootstrapRole, AssumeRole]
```

## Solution: Two-Stack Sequential Deployment

### Architecture
```
Stack 1: Bootstrap Role (No Dependencies)
├── BootstrapRole (OIDC trust, minimal permissions)
└── Outputs: BootstrapRoleArn

Stack 2: Assume Role (Parameter-Based)
├── AssumeRole (infrastructure permissions)
├── Parameters: BootstrapRoleArn (from Stack 1)
└── Outputs: AssumeRoleArn
```

### Key Changes
1. **Separate Stacks**: Split into two independent CloudFormation stacks
2. **Parameter Passing**: BootstrapRoleArn passed as parameter to Stack 2
3. **Sequential Deployment**: Bootstrap stack must deploy before Assume stack
4. **External ID Pattern**: Use AWS account ID instead of role ARN

## Technical Implementation

### Stack 1: Bootstrap Role
**File**: `cloudformation/bootstrap-role.yaml`

**Components**:
- BootstrapRole with GitHub Actions OIDC trust
- Minimal permissions: `sts:AssumeRole` only
- Outputs: `BootstrapRoleArn`, `BootstrapRoleName`

**Security Model**:
- OIDC authentication with GitHub Actions
- Repository-specific subject filtering
- No role dependencies (eliminates circular dependency)

### Stack 2: Assume Role
**File**: `cloudformation/assume-role.yaml`

**Components**:
- AssumeRole with infrastructure deployment permissions
- Parameter: `BootstrapRoleArn` (from Stack 1)
- Outputs: `AssumeRoleArn`, `AssumeRoleName`

**Security Model**:
- Accepts role assumption from BootstrapRole
- External ID validation using AWS account ID
- PowerUserAccess for infrastructure deployment
- Additional S3/DynamoDB permissions for Terraform state

## Deployment Process

### Prerequisites
- AWS credentials configured
- GitHub repository variables ready for configuration
- CloudFormation deployment permissions

### Sequential Deployment

**Step 1: Deploy Bootstrap Stack**
```bash
aws cloudformation deploy \
  --stack-name github-oidc-bootstrap-role \
  --template-file cloudformation/bootstrap-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

**Step 2: Extract BootstrapRoleArn**
```bash
BOOTSTRAP_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name github-oidc-bootstrap-role \
  --query "Stacks[0].Outputs[?OutputKey=='BootstrapRoleArn'].OutputValue" \
  --output text)
```

**Step 3: Deploy Assume Stack**
```bash
aws cloudformation deploy \
  --stack-name github-oidc-assume-role \
  --template-file cloudformation/assume-role.yaml \
  --parameter-overrides BootstrapRoleArn=$BOOTSTRAP_ROLE_ARN \
  --capabilities CAPABILITY_NAMED_IAM
```

**Step 4: Extract AssumeRoleArn**
```bash
ASSUME_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name github-oidc-assume-role \
  --query "Stacks[0].Outputs[?OutputKey=='AssumeRoleArn'].OutputValue" \
  --output text)
```

**Step 5: Configure GitHub Repository Variables**
- `AWS_BOOTSTRAP_ROLE_ARN`: BootstrapRoleArn from Step 2
- `AWS_ASSUME_ROLE_ARN`: AssumeRoleArn from Step 4
- `AWS_REGION`: Target AWS region (e.g., us-east-1)

## Validation

### Automated Checks
All acceptance criteria are machine-verifiable:

```bash
# Validate bootstrap stack
aws cloudformation validate-template --template-body file://cloudformation/bootstrap-role.yaml

# Validate assume stack
aws cloudformation validate-template --template-body file://cloudformation/assume-role.yaml

# Verify bootstrap stack outputs
aws cloudformation describe-stacks --stack-name github-oidc-bootstrap-role --query "Stacks[0].Outputs"

# Verify assume stack outputs
aws cloudformation describe-stacks --stack-name github-oidc-assume-role --query "Stacks[0].Outputs"
```

### Manual Validation
1. Check CloudFormation console for successful stack creation
2. Verify both roles exist in IAM console
3. Test role chaining with GitHub Actions workflow
4. Confirm no circular dependency errors in deployment logs

## Benefits

### Dependency Resolution
- **Eliminates Circular Dependency**: Two independent stacks with parameter passing
- **Sequential Deployment**: Clear dependency order (bootstrap → assume)
- **Parameter-Based References**: No inter-resource references

### Security Model Maintained
- **OIDC Authentication**: GitHub Actions trust relationship preserved
- **Role Chaining**: Bootstrap → Assume pattern maintained
- **External ID Validation**: Security boundary enforcement with account ID
- **Least Privilege**: Bootstrap role has minimal permissions

### Operational Improvements
- **Cleaner Architecture**: Separation of concerns between bootstrap and assume roles
- **Easier Debugging**: Independent stack deployment and troubleshooting
- **Better Maintainability**: Clear dependency chain and parameter passing
- **Scalability**: Pattern can be extended for additional role layers

## Files Modified

### Created
- `cloudformation/bootstrap-role.yaml` - Bootstrap role stack (58 lines)
- `cloudformation/assume-role.yaml` - Assume role stack (58 lines)

### Deleted
- `cloudformation/github-oidc-roles.yaml` - Old circular dependency template

### Updated
- `specs/000-8-cloudformation-circular-dependency-fix/spec.md` - Two-stack architecture
- `specs/000-8-cloudformation-circular-dependency-fix/plan.md` - Sequential deployment stages
- `specs/000-8-cloudformation-circular-dependency-fix/tasks.md` - Updated task execution graph
- `specs/000-8-cloudformation-circular-dependency-fix/checklists/requirements.md` - Two-stack validation

## Related Documentation
- [AWS IAM Role Chaining](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)
- [GitHub Actions AWS Authentication](https://github.com/aws-actions/configure-aws-credentials)
- [CloudFormation Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html)
- [Spec: CloudFormation Circular Dependency Fix](./spec.md)
- [Plan: Architecture Delta](./plan.md)
- [Tasks: Execution Graph](./tasks.md)

## Status
✅ **Completed** - Two-stack architecture implemented and ready for AWS deployment. Circular dependency successfully resolved through parameter-based references and sequential deployment.