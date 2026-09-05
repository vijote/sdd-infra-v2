# Execution Graph (DAG): Assume Role IAM Permissions

**Input**: Design documents from `/specs/003-0-assume-role-iam-permissions/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + user-managed stack update + CI verification

---

## Stage 1: CloudFormation Template Correction

- [x] T001 [Stage 1: Template] Add `TerraformIamAccess` inline policy (`iam:*` on `*`) to the `AssumeRole` resource's `Policies` list in `cloudformation/assume-role.yaml`, alongside the existing `TerraformStateAccess` policy

---

## Stage 2: Stack Update (user-managed — never by the agent)

- [x] T002 [Stage 2: Deploy] Update the assume-role CloudFormation stack with the corrected template (`aws cloudformation update-stack --stack-name <assume-role-stack> --template-body file://cloudformation/assume-role.yaml --capabilities CAPABILITY_NAMED_IAM`) (Depends on T001) - *User-managed*

---

## Stage 3: Verification (CI-only — executed in GitHub Actions, never locally)

- [x] T003 [Stage 3: Verify] AC-001: Template declares the policy (`grep -q 'PolicyName: TerraformIamAccess' cloudformation/assume-role.yaml && grep -q 'iam:\*' cloudformation/assume-role.yaml`) (Depends on T001)
- [x] T004 [Stage 3: Verify] AC-002: Policy attached to the live role (`aws iam get-role-policy --role-name github-actions-assume-role --policy-name TerraformIamAccess --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'iam:\*'`) (Depends on T002)
- [x] T005 [Stage 3: Verify] AC-003: 003-1 IAM role exists after re-run of apply (`aws iam get-role --role-name sdd-k8s-platform-node-role --query 'Role.Arn' --output text`) (Depends on T002)
- [x] T006 [Stage 3: Verify] AC-004: Instance profile references the role (`aws iam get-instance-profile --instance-profile-name sdd-k8s-platform-node-profile --query 'InstanceProfile.Roles[0].Arn' --output text | grep -q 'sdd-k8s-platform-node-role'`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─┬─ T002 ─┬─ T004
      │        └─ T005 ─ T006
      └─ T003
```

- **Sequential**: T001 → T002 (template must be committed before the stack update)
- **CI fan-out**: T003 runs independently after T001; T004/T005 in parallel after T002; T006 after T005
- **Ordering constraint**: T002 MUST complete before the 003-1 apply re-run, or the same 403 recurs

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle)
- **No Terraform changes**: `terraform/modules/cluster-plumbing/` and dev wiring are untouched
- **Deployment**: T002 is user-managed (constitution principles 5 & 6 — no local AWS CLI by the agent)
- **Verification**: Stage 3 tasks run in GitHub Actions CI only (constitution principles 5, 6, 8) — never locally
