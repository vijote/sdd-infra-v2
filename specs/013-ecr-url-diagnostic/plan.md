# Architecture Delta: ECR URL Diagnostic Workflow

**Branch**: `013-ecr-url-diagnostic` | **Date**: 2026-09-19 | **Spec**: [specs/013-ecr-url-diagnostic/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-output-diag.yml` | Create | Manual-dispatch-only workflow: role chain → `terraform init` → `terraform output` for `ecr_frontend_repository_url` + `ecr_backend_repository_url` |

No Terraform, module, IAM, SSM-parameter, or manifest changes. The workflow is read-only against state.

### 1.1 Exact Edits

**Edit A** — `.github/workflows/terraform-output-diag.yml` (new, full YAML in spec §1.1):
- `on: workflow_dispatch` only — no `push`/`pull_request` triggers.
- `env` block: `AWS_REGION`, `AWS_BOOTSTRAP_ROLE_ARN`, `AWS_TERRAFORM_ROLE`, `TF_VAR_state_bucket_name` (all pre-existing repo vars).
- `permissions: id-token: write, contents: read`; `environment: production`.
- Steps: checkout → setup-terraform (>=1.5.0) → configure-aws-credentials (bootstrap role) → configure-aws-credentials (target role, `role-chaining: true`) → `terraform init` (same backend config as `terraform-apply.yml`) → `terraform output ecr_frontend_repository_url` + `terraform output ecr_backend_repository_url` (echoed with section headers).
- `env` on the run step: `TF_VAR_state_bucket_name`, `TF_VAR_region`.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — no new AWS resources, no IAM, no state mutation.
- **Cluster Control Plane & Core Addons**: unchanged.
- **Platform Services**: unchanged.
- **Application Workloads**: unchanged.
- **New artifact**: one GitHub Actions workflow file — the only change.
- **Dependency Flow**: none (leaf workflow; nothing depends on it). No cycle risk.
- **Auth boundaries**: reuses the existing two-tier OIDC role chain (bootstrap → `AWS_TERRAFORM_ROLE`); `terraform output` is read-only (no plan/apply).

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Workflow file**: commit `.github/workflows/terraform-output-diag.yml` to the branch; it does not trigger on push, so the existing apply pipeline is unaffected.
2. **Stage 2 - Manual dispatch**: user runs "Terraform Output Diagnostics (one-off)" via workflow_dispatch; the run log prints both ECR URL values.
3. **Stage 3 - Verdict (drives the fix spec)**:
   - Real `*.dkr.ecr.*.amazonaws.com` URLs → state is fine; the 011 substitution path is broken another way (next diagnostic: decoded SSM command).
   - Empty values → state has empty `repository_url`; fix spec forces a state refresh of the two `aws_ecr_repository` resources.

## 4. Verification Gates

- **YAML Validation**: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/terraform-output-diag.yml'))"` (AC-001).
- **Trigger Guard**: `grep -cE '^  (push|pull_request):' .github/workflows/terraform-output-diag.yml` returns `0` (AC-002).
- **Role Chain**: `grep -c 'role-chaining: true' .github/workflows/terraform-output-diag.yml` returns `1` (AC-003).
- **Runtime Verification** (user-managed, GitHub Actions): manual dispatch completes exit 0 and prints both URL values (AC-004); verdict recorded (AC-005).
