# Plan: CloudFormation Circular Dependency Fix - Two-Stack Approach

**Branch**: `000-8-cloudformation-circular-dependency-fix` | **Date**: 2026-09-02 | **Spec**: specs/000-8-cloudformation-circular-dependency-fix/spec.md

## Problem Analysis

**Root Cause**: BootstrapRole and AssumeRole have mutual resource dependencies that CloudFormation cannot resolve:
- BootstrapRole policy references AssumeRole (Resource field)
- AssumeRole trust policy references BootstrapRole (Principal field)

**Failed Approach**: Replacing `!GetAtt` with `!Ref` doesn't solve the circular dependency - both create resource dependencies.

## Solution: Two-Stack Sequential Deployment

### Architecture

**Stack 1: Bootstrap Role Stack**
- Single resource: BootstrapRole only
- No dependencies on other IAM roles
- Outputs: BootstrapRole ARN and name

**Stack 2: Assume Role Stack** 
- Single resource: AssumeRole only
- Takes BootstrapRole ARN as parameter (not resource reference)
- No circular dependencies

### Deployment Sequence

1. **Deploy Stack 1**: `github-oidc-bootstrap-role` → Creates BootstrapRole
2. **Get Outputs**: Extract BootstrapRole ARN from Stack 1 outputs
3. **Deploy Stack 2**: `github-oidc-assume-role` with BootstrapRole ARN parameter → Creates AssumeRole

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/bootstrap-role.yaml` | Create | BootstrapRole with OIDC trust, outputs role ARN |
| `cloudformation/assume-role.yaml` | Create | AssumeRole with BootstrapRole ARN parameter, outputs role ARN |
| `cloudformation/github-oidc-roles.yaml` | Delete | Remove circular dependency template |
| `specs/000-8-cloudformation-circular-dependency-fix/spec.md` | Modify | Update contracts for two-stack approach |
| `specs/000-8-cloudformation-circular-dependency-fix/plan.md` | Modify | Update architecture delta for sequential deployment |
| `specs/000-8-cloudformation-circular-dependency-fix/tasks.md` | Modify | Update tasks for two-stack deployment sequence |

## 2. Architectural Boundaries & Dependency Flow

- **Stack 1 Layer**: BootstrapRole (OIDC trust, minimal permissions, no role dependencies)
- **Parameter Bridge Layer**: BootstrapRole ARN passed as parameter to Stack 2 (eliminates resource reference)
- **Stack 2 Layer**: AssumeRole (infrastructure permissions, accepts BootstrapRole ARN parameter)
- **Security Boundaries**: External ID condition using role name/ARN parameter for cross-account security
- **GitHub Actions Integration**: Role chaining maintained, both role ARNs configured as repository variables

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Bootstrap Stack Creation**: Create `cloudformation/bootstrap-role.yaml` with BootstrapRole only
2. **Stage 2 - Bootstrap Stack Deployment**: Deploy bootstrap stack and extract role ARN outputs
3. **Stage 3 - Assume Stack Creation**: Create `cloudformation/assume-role.yaml` with AssumeRole and BootstrapRole ARN parameter
4. **Stage 4 - Assume Stack Deployment**: Deploy assume stack with BootstrapRole ARN parameter
5. **Stage 5 - Cleanup**: Remove old circular dependency template
6. **Stage 6 - GitHub Configuration**: Update repository variables with both role ARNs

## 4. Verification Gates

- **Bootstrap Stack Validation**: `aws cloudformation validate-template --template-body file://cloudformation/bootstrap-role.yaml`
- **Bootstrap Stack Deployment**: `aws cloudformation deploy --stack-name github-oidc-bootstrap-role --template-file cloudformation/bootstrap-role.yaml --capabilities CAPABILITY_NAMED_IAM`
- **Bootstrap Output Extraction**: `aws cloudformation describe-stacks --stack-name github-oidc-bootstrap-role --query "Stacks[0].Outputs[?OutputKey=='BootstrapRoleArn'].OutputValue" --output text`
- **Assume Stack Validation**: `aws cloudformation validate-template --template-body file://cloudformation/assume-role.yaml`
- **Assume Stack Deployment**: `aws cloudformation deploy --stack-name github-oidc-assume-role --template-file cloudformation/assume-role.yaml --parameter-overrides BootstrapRoleArn=<ARN> --capabilities CAPABILITY_NAMED_IAM`
- **Role ARN Verification**: `aws cloudformation describe-stacks --stack-name github-oidc-assume-role --query "Stacks[0].Outputs" | grep -E "BootstrapRoleArn|AssumeRoleArn"`

## 5. Key Technical Decisions

### Parameter-Based References
- Use CloudFormation parameters instead of resource references
- BootstrapRole ARN passed as string parameter to AssumeRole stack
- Eliminates circular dependency by removing inter-resource references

### Role Name Strategy
- Keep existing role names: `github-actions-bootstrap-role`, `github-actions-assume-role`
- Use role names in external ID condition instead of ARN references
- Maintains backward compatibility with existing GitHub Actions configuration

### External ID Pattern
- Use role name or ARN string as external ID (not resource reference)
- Maintains security boundary while eliminating circular dependency
- Format: `sts:ExternalId: !Ref AWS::AccountId` (account ID as external ID)

### Stack Naming
- Stack 1: `github-oidc-bootstrap-role`
- Stack 2: `github-oidc-assume-role`
- Clear separation and sequential deployment order