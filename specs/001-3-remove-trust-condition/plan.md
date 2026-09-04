# Architecture Delta: Remove Trust Condition from Assume Role

**Branch**: `001-3-remove-trust-condition` | **Date**: 2026-09-02 | **Spec**: specs/001-3-remove-trust-condition/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/assume-role.yaml` | Modify | Remove Condition block from AssumeRolePolicyDocument |

## 2. Architectural Boundaries & Dependency Flow

- **IAM Layer (AWS & CloudFormation)**: GitHub Actions assume role with simplified trust policy
- **STS Permissions Layer**: sts:AssumeRole and sts:TagSession without restrictive conditions
- **Trust Relationship Layer**: Principal-based trust only (BootstrapRoleArn)
- **Shared Dependencies**: Existing PowerUserAccess and TerraformStateAccess policies

## 3. Provisioning & Rollout Stages

1. **Stage 1 - CloudFormation Update**: Deploy updated assume-role.yaml without Condition block
2. **Stage 2 - Role Testing**: Verify GitHub Actions can assume role with session tags