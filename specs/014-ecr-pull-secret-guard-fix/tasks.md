# Execution Graph (DAG): ECR Pull Secret Guard Fix

**Input**: Design documents from `/specs/014-ecr-pull-secret-guard-fix/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 2 verification gates

## Stage 1: Implementation

- [ ] T001 [Stage 1: Script] In `terraform/environments/dev/scripts/create-ecr-pull-secret.sh`: replace the guard (lines 9–12) — change `if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "%%ECR_REGISTRY%%" ]; then` to `if [ -z "$REGISTRY" ]; then` and the error message `ERROR: REGISTRY not substituted` to `ERROR: REGISTRY is empty`. After the edit exactly one `%%ECR_REGISTRY%%` occurrence must remain (line 7). Keep the file executable.
- [ ] T002 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`, `null_resource.apply_ecr_pull_secret` triggers map: add `script_rev   = "014-guard-fix"` (static string) alongside the existing `ecr_repo_url` and `instance_id` triggers, to force the provisioner to re-run on the next apply (Depends on T001)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001/AC-002/AC-003 static: (1) `grep -c '%%ECR_REGISTRY%%' terraform/environments/dev/scripts/create-ecr-pull-secret.sh` returns `1`, (2) `grep -c 'if \[ -z "$REGISTRY" \]; then' terraform/environments/dev/scripts/create-ecr-pull-secret.sh` returns `1`, (3) `grep -c 'script_rev   = "014-guard-fix"' terraform/environments/dev/main.tf` returns `1`; plus `terraform fmt -check -recursive && terraform validate`
- [ ] T004 [Stage 2: Verify] AC-004/AC-005: (1) next `terraform apply` (push to `main`) re-runs `apply_ecr_pull_secret` and the CI log shows `ECR pull secret created successfully`, (2) `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'` → `kubernetes.io/dockerconfigjson`, (3) `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.data.\\.dockerconfigjson}' | base64 -d | python3 -m json.tool` → `.auths` key = `891377205721.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`, username `AWS`
