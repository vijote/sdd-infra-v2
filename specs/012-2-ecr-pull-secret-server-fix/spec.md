# Spec: ECR Pull Secret Server Fix

**Feature Branch**: `012-2-ecr-pull-secret-server-fix` | **Date**: 2026-09-23 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Fix `--docker-server` value in `terraform/environments/dev/scripts/create-ecr-pull-secret.sh`; no new AWS resources.
- **Kubernetes / Cluster Scope**: `ecr-pull-secret` in `sdd-apps` recreated with `auths` key = bare registry host (kubelet matches registry host only; full repo URL key never matches → `ErrImagePull: no basic auth credentials`).
- **Target Services / Modules**: `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` (single defect), `terraform/environments/dev/main.tf` (`script_rev` trigger bump on `apply_ecr_pull_secret`).
- **Security & CI/CD**: Unchanged. Node role retains `AmazonEC2ContainerRegistryReadOnly`; no IAM/SG changes.

### 1.1 Terraform / HCL Resource Contracts
```hcl
# null_resource "apply_ecr_pull_secret" (main.tf):
#   triggers.script_rev = "012-2-server-fix"   # bump from "014-guard-fix" to force re-run
#   (all other triggers/depends_on unchanged)
# Terraform replace() chain unchanged: %%ECR_REGISTRY%% -> module.ecr.repository_urls["sdd-k8s-platform/frontend"]
# (single placeholder occurrence, 014 gotcha)
```

### 1.2 Script Contract (create-ecr-pull-secret.sh)
```bash
# BEFORE (defect): REGISTRY = full repository URL
#   891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend
# AFTER (fix): REGISTRY = bare registry host
#   891377205721.dkr.ecr.us-east-1.amazonaws.com
# Implementation: strip the repository path from the substituted value:
#   REGISTRY="${REGISTRY%%/*}"   # keep host only (first "/" and everything after removed)
# Guard stays a -z empty check (014 gotcha: single %%ECR_REGISTRY%% occurrence, line 7 only)
# --docker-server="$REGISTRY" now produces auths key = bare registry host
```

### 1.3 Data & Storage Contracts
- None. Secret `ecr-pull-secret` (type `kubernetes.io/dockerconfigjson`) recreated in-place with corrected `auths` key + fresh 12h token.

### 1.4 Network & Security Contracts
- No new SG rules, no API server exposure, no IAM changes. kubectl remains control-plane-only via SSM.
- ECR token still minted on the control plane via node role (`ecr:GetAuthorizationToken`).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: `grep -c 'REGISTRY="%%ECR_REGISTRY%%"' scripts/create-ecr-pull-secret.sh` returns 1 (single placeholder occurrence)
- [ ] AC-003: Post-apply, `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.data.dockerconfigjson}' | base64 -d` shows `auths` key exactly `891377205721.dkr.ecr.us-east-1.amazonaws.com` (no repo path)
- [ ] AC-004: Post-apply, `kubectl rollout status deployment/app-backend -n sdd-apps` succeeds with ECR image (pull succeeds with fresh token)
- [ ] AC-005: `terraform plan -detailed-exitcode` shows only `apply_ecr_pull_secret` trigger update (`script_rev`), no destroy

## 3. Assumptions & Technical Constraints
- **Root cause (011 defect)**: script passed the full 010 repository URL as `--docker-server`; kubelet requires the bare registry host as the `auths` key.
- **Cluster recreation**: user recreates the cluster before applying; `instance_id` trigger re-runs all resources on the new control plane.
- **IAM**: Unchanged. Deploy role retains SSM SendCommand + ECR permissions.
- **Placeholder rule**: `%%ECR_REGISTRY%%` appears exactly once (assignment line); guards use `-z` checks (014 gotcha).
- **Testing Policy**: No validation steps in workflows; user handles all testing (constitution §6).
