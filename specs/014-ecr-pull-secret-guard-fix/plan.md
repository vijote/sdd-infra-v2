# Architecture Delta: ECR Pull Secret Guard Fix

**Branch**: `014-ecr-pull-secret-guard-fix` | **Date**: 2026-09-19 | **Spec**: [specs/014-ecr-pull-secret-guard-fix/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` | Modify | Guard fix: drop the `%%ECR_REGISTRY%%` comparison (self-referential after substitution); keep `-z` empty check |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_ecr_pull_secret`: add `script_rev = "014-guard-fix"` trigger to force re-run |

No module, IAM, SSM-parameter, workflow, or manifest changes.

### 1.1 Exact Edits

**Edit A** — `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` (lines 9–12):
- Replace `if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "%%ECR_REGISTRY%%" ]; then` with `if [ -z "$REGISTRY" ]; then`.
- Replace the error message `ERROR: REGISTRY not substituted` with `ERROR: REGISTRY is empty`.
- After the edit, exactly one `%%ECR_REGISTRY%%` occurrence remains (line 7) — the `replace()` in main.tf touches only that line.

**Edit B** — `terraform/environments/dev/main.tf`, `null_resource.apply_ecr_pull_secret` triggers map:
- Add `script_rev   = "014-guard-fix"` (static string; forces the provisioner to re-run once on the next apply).
- No change to `ecr_repo_url`, `instance_id`, `depends_on`, or the SSM command.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — no new AWS resources, no IAM, no state mutation.
- **Cluster Control Plane & Core Addons**: unchanged.
- **Platform Services**: unchanged.
- **Application Workloads**: unchanged (still on the public image baseline; swap is spec 012).
- **New artifact**: none — the fix makes the existing 011 artifact (`ecr-pull-secret`) actually get created.
- **Dependency Flow**: unchanged — `apply_app_infrastructure` → `apply_ecr_pull_secret` (leaf). No cycle risk.
- **Auth boundaries**: unchanged — ECR token minted on the control plane at runtime; never in state or the command document.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` (existing `terraform-apply.yml`, push to `main`) — the `script_rev` trigger bump re-runs `apply_ecr_pull_secret`; the SSM script now passes the guard, mints a fresh ECR token, and creates `ecr-pull-secret` in `sdd-apps`. Every other resource no-ops.
2. **Stage 2 - Downstream (spec 012, after first real push)**: manifest-swap spec adds `imagePullSecrets: [ecr-pull-secret]` + ECR image refs — now unblocked.

## 4. Verification Gates

- **Static (agent-runnable, no AWS)**: AC-001/AC-002/AC-003 greps (placeholder count = 1, empty-check present, trigger bump present).
- **IaC Validation**: `terraform fmt -check -recursive && terraform validate` (no HCL syntax change expected, but the trigger map is touched).
- **Runtime Verification** (user-managed, CI): next apply log shows `ECR pull secret created successfully` (AC-004).
- **Secret Verification** (user-managed CLI): `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'` → `kubernetes.io/dockerconfigjson`; decoded `.data."\.dockerconfigjson"` → `.auths` key = `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`, username `AWS` (AC-005).
