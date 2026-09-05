# Architecture Delta: Assume Role IAM Permissions

**Branch**: `003-0-assume-role-iam-permissions` | **Date**: 2026-09-05 | **Spec**: specs/003-0-assume-role-iam-permissions/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `cloudformation/assume-role.yaml` | Modify | Add `TerraformIamAccess` inline policy (`iam:*` on `*`) to the `AssumeRole` resource's `Policies` list, alongside the existing `TerraformStateAccess` |

**No other files change.** Terraform modules, dev environment, and workflows are untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives entirely in the CloudFormation-managed IAM layer — outside Terraform state
- **Auth chain (unchanged)**: GitHub OIDC → `github-actions-bootstrap-role` → `github-actions-assume-role` (role chaining)
- **Effect**: `github-actions-assume-role` gains `iam:*`, unblocking 003-1's `aws_iam_role` / `aws_iam_instance_profile` resources
- **Precedent**: `TerraformStateAccess` already uses the same inline-policy pattern (scoped `s3:*`/`dynamodb:*`); `TerraformIamAccess` follows it with the user-approved wildcard scope

## 3. Provisioning & Rollout Stages

- **Stage 1 — Template edit (agent)**: Add the `TerraformIamAccess` policy block to `cloudformation/assume-role.yaml`
- **Stage 2 — Stack update (user-managed)**: `aws cloudformation update-stack` against the assume-role stack (constitution principles 5 & 6 — no local AWS CLI by the agent)
- **Stage 3 — Re-run 003-1 apply (CI)**: Push/merge triggers `terraform-apply.yml`; the 2 security groups from the failed run are already in state, so Terraform resumes at the IAM role and completes the 6-resource plan

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `grep -q 'PolicyName: TerraformIamAccess' cloudformation/assume-role.yaml && grep -q 'iam:\*' cloudformation/assume-role.yaml`
- **AC-002**: `aws iam get-role-policy --role-name github-actions-assume-role --policy-name TerraformIamAccess --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'iam:\*'`
- **AC-003**: `aws iam get-role --role-name sdd-k8s-platform-node-role --query 'Role.Arn' --output text`
- **AC-004**: `aws iam get-instance-profile --instance-profile-name sdd-k8s-platform-node-profile --query 'InstanceProfile.Roles[0].Arn' --output text | grep -q 'sdd-k8s-platform-node-role'`

## 5. Risks & Mitigations

- **Wildcard IAM scope**: Accepted user decision (dev-only, education project). Reachability is still bounded by the OIDC → bootstrap → role-chaining trust chain; no static credentials exist
- **Stack update failure**: CloudFormation rolls back automatically; the previous template remains live
- **Ordering**: Stack update MUST precede the 003-1 apply re-run, or the same 403 recurs
