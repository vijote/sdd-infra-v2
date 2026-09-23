# Architecture Delta: ECR Pull Secret Server Fix

**Branch**: `012-2-ecr-pull-secret-server-fix` | **Date**: 2026-09-23 | **Spec**: [specs/012-2-ecr-pull-secret-server-fix/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` | Modify | Strip repository path from `%%ECR_REGISTRY%%` substitution: add `REGISTRY="${REGISTRY%%/*}"` after the assignment; `--docker-server="$REGISTRY"` now yields `auths` key = bare registry host |
| `terraform/environments/dev/main.tf` | Modify | Bump `apply_ecr_pull_secret` `triggers.script_rev` from `"014-guard-fix"` to `"012-2-server-fix"` to force one re-run (014 gotcha: provisioner-only changes don't re-run) |

No new Terraform modules. No new AWS resources. No new K8s API objects. No manifest changes (012 placeholders unaffected — the substitution value is the same registry URL; only the script's derived `--docker-server` changes).

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: Unchanged. Same ECR repos (010), SSM parameters, OIDC role-chaining.
- **Cluster Control Plane & Core Addons**: Unchanged. kubectl remains control-plane-only via SSM.
- **Platform Services**: Unchanged (ingress-nginx, cert-manager untouched).
- **Application Workloads**: `ecr-pull-secret` recreated in-place with corrected `auths` key + fresh 12h token; `app-backend` / `app-frontend` pull path unblocked (012 manifests already reference the secret).
- **Shared Dependencies**: 014 gotchas (single `%%ECR_REGISTRY%%` occurrence, `-z` guard, `script_rev` bump for re-run); K8s 1.28.0 strict decoding (no manifest changes).

Dependency flow: terraform apply → `apply_ecr_pull_secret` re-runs (script_rev bump) → SSM send-command → control plane runs fixed script → `ecr-pull-secret` recreated with bare-host `auths` key → kubelet matches registry host → ECR pull succeeds.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Script Fix**: Correct `--docker-server` in `create-ecr-pull-secret.sh` (host-only strip).
2. **Stage 2 - Trigger Bump**: `script_rev` = `012-2-server-fix` in `apply_ecr_pull_secret` triggers.
3. **Stage 3 - Cluster Apply**: User recreates the cluster; `instance_id` trigger re-runs all resources on the new control plane; fixed script creates the secret correctly from the start.
4. **Stage 4 - Workloads**: `apply_app_backend` / `apply_app_frontend_ingress` apply 012 manifests; pods pull ECR images via the corrected secret.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (only `script_rev` trigger update, no destroy)
- **Script Validation**: `grep -c 'REGISTRY="%%ECR_REGISTRY%%"' scripts/create-ecr-pull-secret.sh` returns 1 (single occurrence)
- **Service Rollout**: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=180s` (post-apply, ECR image pull succeeds)
- **Resource Verification**: `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.data.dockerconfigjson}' | base64 -d` → `auths` key = bare registry host
- **Testing Policy**: No validation steps inside workflow definitions; user handles all testing (constitution §6).
