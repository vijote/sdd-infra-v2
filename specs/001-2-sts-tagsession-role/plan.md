# Architecture Delta: STS TagSession Role Enhancement

**Branch**: `001-2-sts-tagsession-role` | **Date**: 2026-09-02 | **Spec**: specs/001-2-sts-tagsession-role/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/assume-role.yaml` | Modify | Add sts:TagSession permission to AssumeRolePolicyDocument |

## 2. Architectural Boundaries & Dependency Flow

- **IAM Layer (AWS & CloudFormation)**: GitHub Actions assume role with STS permissions
- **STS Permissions Layer**: sts:AssumeRole (existing) and sts:TagSession (new)
- **Trust Relationship Layer**: Bootstrap role ARN with ExternalId condition
- **Shared Dependencies**: Existing PowerUserAccess and TerraformStateAccess policies

## 3. Provisioning & Rollout Stages

1. **Stage 1 - CloudFormation Update**: Deploy updated assume-role.yaml with sts:TagSession permission
2. **Stage 2 - Role Testing**: Verify GitHub Actions can assume role with session tags