# Architecture Delta: Node Role SSM Permissions

**Branch**: `003-0-node-role-ssm-permissions` | **Date**: 2026-09-05 | **Spec**: specs/003-0-node-role-ssm-permissions/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Add `aws_iam_role_policy.node_ssm_parameters` inline policy (`ssm:PutParameter` + `ssm:GetParameter` on `parameter/sdd-k8s-platform/*`) to the existing `aws_iam_role.node` |

**No other files change.** Dev environment, workflows, and all other modules are untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix lives in the Terraform-managed IAM layer (003-1's module) — no CloudFormation, no new resources
- **Node role (unchanged core)**: `sdd-k8s-platform-node-role` — EC2 trust, `AmazonSSMManagedInstanceCore` (receive commands), `AmazonEC2ContainerRegistryReadOnly` (pull images)
- **New inline policy**: `sdd-k8s-platform-node-ssm-parameters` — grants the Parameter Store read/write channel the managed policy does not cover
- **Consumers**:
  - 003-2 control plane user-data → `ssm:PutParameter` (publish `kubeadm join` command)
  - 003-3 worker user-data → `ssm:GetParameter` (fetch join command)
- **Shared profile**: control plane + workers use the same instance profile, so one role change covers both paths

## 3. Provisioning & Rollout Stages

- **Stage 1 — Module edit (agent)**: Add the `aws_iam_role_policy` resource to `terraform/modules/cluster-plumbing/main.tf`
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; in-place update of the role (adds inline policy) — no replacement, no impact on running nodes
- **Stage 3 — Unblocks 003-2**: Control plane launch can now publish the join command without 403

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `terraform plan -detailed-exitcode`
- **AC-003**: `aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'ssm:PutParameter'`
- **AC-004**: `aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Resource[0]' --output text | grep -q 'parameter/sdd-k8s-platform/\*'`

## 5. Risks & Mitigations

- **Least-privilege scope**: Actions limited to `ssm:PutParameter`/`ssm:GetParameter`; resource limited to `parameter/sdd-k8s-platform/*` — no wildcard over all SSM
- **In-place update**: Adding an inline policy never forces role/profile replacement; running nodes keep current credentials until relaunched
- **Ordering**: MUST be applied before 003-2's control plane launches, or the `put-parameter` step in its user-data 403s
- **Rollback**: Remove the `aws_iam_role_policy.node_ssm_parameters` resource and re-apply
