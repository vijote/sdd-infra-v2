# Execution Graph (DAG): Node Role SSM Permissions

**Input**: Design documents from `/specs/003-0-node-role-ssm-permissions/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification

---

## Stage 1: Module Correction

- [x] T001 [Stage 1: Module] Add `aws_iam_role_policy.node_ssm_parameters` inline policy (`ssm:PutParameter` + `ssm:GetParameter` on `arn:aws:ssm:*:*:parameter/sdd-k8s-platform/*`) to the existing `aws_iam_role.node` in `terraform/modules/cluster-plumbing/main.tf`

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [x] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [x] T003 [Stage 2: Verify] AC-002: Terraform plan generates the inline policy (`terraform plan -detailed-exitcode`) (Depends on T002)
- [x] T004 [Stage 2: Verify] AC-003: Inline policy attached to the live role with `ssm:PutParameter` (`aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'ssm:PutParameter'`) (Depends on T003)
- [x] T005 [Stage 2: Verify] AC-004: Policy resource scoped to `parameter/sdd-k8s-platform/*` (`aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Resource[0]' --output text | grep -q 'parameter/sdd-k8s-platform/\*'`) (Depends on T004)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 (edit → validate → plan → live checks)
- **Ordering constraint**: T001's apply MUST complete before 003-2's control plane launches, or the `put-parameter` step in its user-data 403s

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle)
- **No new resources**: in-place update of the existing node role — no replacement, no impact on running nodes
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
