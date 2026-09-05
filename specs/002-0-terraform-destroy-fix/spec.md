# Spec: Terraform Destroy Workflow Fix

**Feature Branch**: `002-0-terraform-destroy-fix` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (CI/CD workflow correction only — no AWS resource changes)
- **Kubernetes / Cluster Scope**: None
- **Target Services / Modules**: `.github/workflows/terraform-destroy.yml` (manual teardown workflow)
- **Security & CI/CD**: GitHub OIDC role chaining (bootstrap → assume role), S3 remote state backend

### 1.1 Terraform / HCL Resource Contracts
None (no Terraform code changes; this spec corrects the destroy workflow to mirror the working `terraform-apply.yml`)

### 1.2 Kubernetes Manifest / Helm Values Contracts
None

### 1.3 Data & Storage Contracts
- **State Backend**: S3 bucket `sdd-k8s-platform-terraform-state` (dev: `sdd-k8s-platform-terraform-state-dev`), DynamoDB lock table — must be reachable via `terraform init -backend-config`

### 1.4 Workflow Contract (GitHub Actions)
The destroy workflow MUST mirror the working `terraform-apply.yml` auth + backend pattern:

```yaml
# Required corrections to .github/workflows/terraform-destroy.yml
# 1. Working directory: all terraform steps run in terraform/environments/dev
# 2. Backend config: terraform init -backend-config="bucket=..." -backend-config="region=..."
# 3. Auth: 2-step role chain (bootstrap OIDC -> assume role), NO role-external-id
# 4. Required vars: TF_VAR_state_bucket_name, TF_VAR_region
# 5. Remove stale vars: TF_VAR_github_owner, TF_VAR_github_repo, TF_VAR_mysql_root_password, TF_VAR_mysql_password
# 6. Retain: workflow_dispatch + type-"destroy" confirmation gate (justified manual gate for destructive op)
```

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Workflow YAML is valid (`actionlint .github/workflows/terraform-destroy.yml` exits 0)
- [ ] AC-002: Destroy workflow runs `terraform init` with `-backend-config` for bucket and region (grep workflow for `-backend-config="bucket=`)
- [ ] AC-003: Destroy workflow runs terraform steps from `terraform/environments/dev` (grep workflow for `cd terraform/environments/dev`)
- [ ] AC-004: Destroy workflow uses 2-step role chain without `role-external-id` (grep workflow: `role-chaining: true` present, `role-external-id` absent)
- [ ] AC-005: Destroy workflow passes `TF_VAR_state_bucket_name` (grep workflow for `TF_VAR_state_bucket_name`)
- [ ] AC-006: Destroy workflow contains no stale vars (grep workflow: `TF_VAR_mysql_root_password`, `TF_VAR_mysql_password`, `TF_VAR_github_owner`, `TF_VAR_github_repo` all absent)
- [ ] AC-007: Destroy workflow retains the type-"destroy" confirmation gate (grep workflow for `github.event.inputs.confirm`)

## 3. Assumptions & Technical Constraints
- **Reference Workflow**: `terraform-apply.yml` is the working reference (confirmed passing); destroy must match its auth + backend + working-dir pattern
- **Auth Model**: Bootstrap role (OIDC) → assume role (PowerUserAccess + state access) via `role-chaining: true`; the assume role's trust policy has no ExternalId condition, so `role-external-id` MUST NOT be set
- **Manual Gate Justification**: `workflow_dispatch` + type-"destroy" confirmation is a deliberate deviation from the no-manual-gates policy — destroy is a destructive teardown, not a deployment, and must not fire on push
- **State Prerequisite**: S3 state bucket + DynamoDB lock table must exist (provisioned by `001-state-backend`) before destroy can run
- **Testing Policy**: No unit or E2E test generation - validation performed via workflow linting and grep-based contract checks in CI
- **Tooling**: `actionlint` for workflow YAML validation; no local AWS CLI or Terraform execution
