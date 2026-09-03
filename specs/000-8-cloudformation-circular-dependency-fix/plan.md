# Architecture Delta: CloudFormation Circular Dependency Fix

**Branch**: `000-8-cloudformation-circular-dependency-fix` | **Date**: 2026-09-02 | **Spec**: specs/000-8-cloudformation-circular-dependency-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/bootstrap-role.yaml` | Create | BootstrapRole with OIDC trust, outputs BootstrapRoleArn |
| `cloudformation/assume-role.yaml` | Create | AssumeRole with BootstrapRoleArn parameter, outputs AssumeRoleArn |
| `cloudformation/github-oidc-roles.yaml` | Delete | Remove circular dependency template |

## 2. Architectural Boundaries & Dependency Flow

- **Stack 1 Layer**: BootstrapRole (OIDC trust, minimal permissions, no role dependencies)
- **Parameter Bridge Layer**: BootstrapRoleArn passed as parameter to Stack 2 (eliminates resource reference)
- **Stack 2 Layer**: AssumeRole (infrastructure permissions, accepts BootstrapRoleArn parameter)
- **Security Boundaries**: External ID condition using AWS account ID for cross-account security
- **GitHub Actions Integration**: Role chaining maintained, both role ARNs configured as repository variables

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Bootstrap Stack Creation**: Create `cloudformation/bootstrap-role.yaml` with BootstrapRole only
2. **Stage 2 - Bootstrap Stack Deployment**: Deploy bootstrap stack and extract role ARN outputs
3. **Stage 3 - Assume Stack Creation**: Create `cloudformation/assume-role.yaml` with AssumeRole and BootstrapRoleArn parameter
4. **Stage 4 - Assume Stack Deployment**: Deploy assume stack with BootstrapRoleArn parameter
5. **Stage 5 - Cleanup**: Remove old circular dependency template
6. **Stage 6 - GitHub Configuration**: Update repository variables with both role ARNs

## 4. Verification Gates

- **Bootstrap Stack Validation**: `aws cloudformation validate-template --template-body file://cloudformation/bootstrap-role.yaml`
- **Bootstrap Stack Deployment**: `aws cloudformation deploy --stack-name github-oidc-bootstrap-role --template-file cloudformation/bootstrap-role.yaml --capabilities CAPABILITY_NAMED_IAM`
- **Bootstrap Output Extraction**: `aws cloudformation describe-stacks --stack-name github-oidc-bootstrap-role --query "Stacks[0].Outputs[?OutputKey=='BootstrapRoleArn'].OutputValue" --output text`
- **Assume Stack Validation**: `aws cloudformation validate-template --template-body file://cloudformation/assume-role.yaml`
- **Assume Stack Deployment**: `aws cloudformation deploy --stack-name github-oidc-assume-role --template-file cloudformation/assume-role.yaml --parameter-overrides BootstrapRoleArn=<ARN> --capabilities CAPABILITY_NAMED_IAM`
- **Role ARN Verification**: `aws cloudformation describe-stacks --stack-name github-oidc-assume-role --query "Stacks[0].Outputs" | grep -E "BootstrapRoleArn|AssumeRoleArn"`