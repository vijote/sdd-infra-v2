# Execution Graph (DAG): ECR Pull Secret (in-cluster)

**Input**: Design documents from `/specs/011-ecr-pull-secret/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 2 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Script] Create `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` with the full content from spec §1.2: `set -euo pipefail`; `REGISTRY="%%ECR_REGISTRY%%"` with fail-fast guard (empty or unsubstituted → exit 1); `PASSWORD=$(aws ecr get-login-password)` with empty-check guard; idempotent `KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete secret ecr-pull-secret -n sdd-apps --ignore-not-found` then `kubectl create secret docker-registry ecr-pull-secret -n sdd-apps --docker-server="$REGISTRY" --docker-username=AWS --docker-password="$PASSWORD"`; final echo. Make it executable (`chmod +x`)
- [x] T002 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`: add `null_resource.apply_ecr_pull_secret` (full HCL in spec §1.1) after `null_resource.apply_app_frontend_ingress`, before `set_node_provider_ids`: (1) header comment (011: kubelet does not use the node IAM role for image pulls; token minted on the control plane; ~12h validity), (2) `depends_on = [null_resource.apply_app_infrastructure]` (creates the sdd-apps namespace), (3) `triggers`: `ecr_repo_url = module.ecr.repository_urls["sdd-k8s-platform/frontend"]` + `instance_id = module.control_plane.control_plane_instance_id`, (4) SSM command: `base64encode(replace(file("${path.module}/scripts/create-ecr-pull-secret.sh"), "%%ECR_REGISTRY%%", module.ecr.repository_urls["sdd-k8s-platform/frontend"]))` piped to `bash`, (5) `--comment "Create ECR pull secret in sdd-apps (011)"` (41 chars — under the 100-char SSM cap), (6) SSM-agent wait loop, bootstrap-instance-id gate, and poll loop copied verbatim from `apply_app_backend` (Depends on T001)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY the new `null_resource.apply_ecr_pull_secret`; zero changes to existing resources
- [ ] T004 [Stage 2: Verify] AC-003: (1) `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'` → `kubernetes.io/dockerconfigjson`, (2) `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool` → `.auths` key = `<account_id>.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`, username `AWS`
