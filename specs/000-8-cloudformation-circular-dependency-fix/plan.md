# Architecture Delta: CloudFormation Circular Dependency Fix

**Branch**: `000-8-cloudformation-circular-dependency-fix` | **Date**: 2026-09-02 | **Spec**: specs/000-8-cloudformation-circular-dependency-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/github-oidc-roles.yaml` | Modify | Replace !GetAtt with !Ref to resolve circular dependency between BootstrapRole and AssumeRole |

## 2. Architectural Boundaries & Dependency Flow

- **CloudFormation Layer**: BootstrapRole (OIDC trust, minimal permissions) → AssumeRole (infrastructure permissions, external ID validation)
- **Reference Resolution Layer**: !Ref instead of !GetAtt eliminates circular dependency while maintaining same functionality
- **Security Boundaries**: External ID condition using assume role reference for cross-account security validation
- **GitHub Actions Integration**: Role chaining with 1-hour session duration and repository variable configuration

## 3. Provisioning & Rollout Stages

1. **Stage 1 - CloudFormation Update**: Replace !GetAtt with !Ref in BootstrapRole policy (Resource: !Ref AssumeRole)
2. **Stage 2 - CloudFormation Update**: Replace !GetAtt with !Ref in AssumeRole trust policy (AWS: !Ref BootstrapRole)
3. **Stage 3 - CloudFormation Update**: Replace !GetAtt with !Ref in external ID condition (sts:ExternalId: !Ref AssumeRole)
4. **Stage 4 - Validation**: CloudFormation template validation and deployment testing
5. **Stage 5 - GitHub Configuration**: Update repository variables with new role ARNs after successful deployment

## 4. Verification Gates

- **CloudFormation Validation**: `aws cloudformation validate-template --template-body file://cloudformation/github-oidc-roles.yaml`
- **Circular Dependency Check**: `! grep -A 2 "Resource:" cloudformation/github-oidc-roles.yaml | grep "GetAtt"`
- **Reference Verification**: `grep -q "Resource: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml && grep -q "AWS: !Ref BootstrapRole" cloudformation/github-oidc-roles.yaml`
- **External ID Check**: `grep -q "sts:ExternalId: !Ref AssumeRole" cloudformation/github-oidc-roles.yaml`
- **Deployment Test**: `aws cloudformation deploy --stack-name github-oidc-roles --template-file cloudformation/github-oidc-roles.yaml --capabilities CAPABILITY_NAMED_IAM`
- **Output Verification**: `aws cloudformation describe-stacks --stack-name github-oidc-roles --query "Stacks[0].Outputs" | grep -E "BootstrapRoleArn|AssumeRoleArn"`