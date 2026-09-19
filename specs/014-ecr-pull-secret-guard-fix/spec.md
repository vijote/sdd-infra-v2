# Spec: ECR Pull Secret Guard Fix

**Feature Branch**: `014-ecr-pull-secret-guard-fix` | **Date**: 2026-09-19 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources; no IAM change)
- **Kubernetes / Cluster Scope**: none directly — fixes the SSM script that creates `ecr-pull-secret` in `sdd-apps`
- **Target Services / Modules**: `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` (011) — one-line guard fix; `null_resource.apply_ecr_pull_secret` re-runs via trigger bump
- **Security & CI/CD**: no workflow change — existing `terraform-apply.yml` (push to `main`) applies this spec

> **Why**: 011's apply fails in CI with `ERROR: REGISTRY not substituted` (guard at `create-ecr-pull-secret.sh:9`). Spec 013's diagnostic refuted the empty-state hypothesis: `ecr_frontend_repository_url` = `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend` (real URL in state). Root cause: the Terraform `replace()` substitutes **all** occurrences of `%%ECR_REGISTRY%%` in the script — including the one inside the guard's own comparison. After substitution the guard reads `[ "$REGISTRY" = "<real URL>" ]`, which is always true because `REGISTRY` was just set to that same URL → the guard always fires → `exit 1`. Deterministic bug; re-running never fixes it.

### 1.1 SSM Script Contract (exact edit)

`terraform/environments/dev/scripts/create-ecr-pull-secret.sh` — replace the guard (lines 9–12):

```bash
# BEFORE (broken — the %%ECR_REGISTRY%% literal is itself substituted by Terraform):
if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "%%ECR_REGISTRY%%" ]; then
  echo "ERROR: REGISTRY not substituted" >&2
  exit 1
fi

# AFTER (fixed — empty check only; cannot be broken by the substitution):
if [ -z "$REGISTRY" ]; then
  echo "ERROR: REGISTRY is empty" >&2
  exit 1
fi
```

- The `-z "$REGISTRY"` check alone still catches the real failure case: empty `module.ecr.repository_urls[...]` → `REGISTRY=""`.
- No other line in the script contains `%%ECR_REGISTRY%%` after this edit, so the `replace()` in `main.tf` touches exactly one occurrence (line 7).
- Script stays executable; no other content changes.

### 1.2 Terraform / HCL Resource Contracts

`terraform/environments/dev/main.tf` — `null_resource.apply_ecr_pull_secret` (011): add a trigger bump so the provisioner re-runs on the next apply (the script content is embedded via `file()` at plan time, but the trigger map must change to force re-execution):

```hcl
triggers = {
  ecr_repo_url = module.ecr.repository_urls["sdd-k8s-platform/frontend"] # 010
  instance_id  = module.control_plane.control_plane_instance_id          # 004-10
  script_rev   = "014-guard-fix" # 014: force re-run with the fixed guard
}
```

- `script_rev` is a static string — it changes once (this spec) and never again; future script edits bump it.
- No change to the `replace()` expression, `depends_on`, or SSM command structure.

### 1.3 Data & Storage Contracts

- None (no SSM parameters, no Parameter Store secrets, no state migration).

### 1.4 Network & Security Contracts

- None (no IAM, no SG rules; same SSM Run Command path as 011).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Guard no longer contains the placeholder literal (`grep -c '%%ECR_REGISTRY%%' terraform/environments/dev/scripts/create-ecr-pull-secret.sh` returns `1` — only line 7)
- [ ] AC-002: Guard still fails on empty registry (`grep -c 'if \[ -z "$REGISTRY" \]; then' terraform/environments/dev/scripts/create-ecr-pull-secret.sh` returns `1`)
- [ ] AC-003: Trigger bump present (`grep -c 'script_rev   = "014-guard-fix"' terraform/environments/dev/main.tf` returns `1`)
- [ ] AC-004: Next `terraform apply` (push to `main`) re-runs `apply_ecr_pull_secret` and the SSM invocation reaches `Success` (CI log: `ECR pull secret created successfully`)
- [ ] AC-005: `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'` → `kubernetes.io/dockerconfigjson`; decoded `.data."\.dockerconfigjson"` → `.auths` key = `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`, username `AWS`

## 3. Assumptions & Technical Constraints

- **State is correct**: 013 diagnostic confirmed both ECR URL outputs are real URLs in state — no state refresh needed.
- **Cluster is healthy**: bootstrap complete, SSM registered; no cluster recreation required.
- **Token staleness**: the ECR token in the secret is ~12h; the re-run mints a fresh one (011 behavior, unchanged).
- **Numbering**: `014` (012 reserved for manifest image swap; 013 was the diagnostic).
- **Testing Policy**: No unit or E2E test generation — validation performed directly against AWS infrastructure using CLI tools.
