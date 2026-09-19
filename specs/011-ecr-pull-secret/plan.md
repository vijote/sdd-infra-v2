# Architecture Delta: ECR Pull Secret (in-cluster)

**Branch**: `011-ecr-pull-secret` | **Date**: 2026-09-19 | **Spec**: [specs/011-ecr-pull-secret/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` | Create | SSM script: mint ECR token, idempotent delete+create of `ecr-pull-secret` in `sdd-apps` |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_ecr_pull_secret` (SSM pattern; `%%ECR_REGISTRY%%` replace; depends on `apply_app_infrastructure`) |

No module, IAM, SSM-parameter, or manifest changes. The app manifests keep `nginx:alpine` and gain no `imagePullSecrets` — the swap is spec 012.

### 1.1 Exact Edits

**Edit A** — `terraform/environments/dev/scripts/create-ecr-pull-secret.sh` (new, full content in spec §1.2):
- `set -euo pipefail`; `REGISTRY="%%ECR_REGISTRY%%"` with a fail-fast guard (empty or unsubstituted → exit 1).
- `PASSWORD=$(aws ecr get-login-password)` with an empty-check guard.
- Idempotent: `kubectl delete secret ecr-pull-secret -n sdd-apps --ignore-not-found` then `kubectl create secret docker-registry ecr-pull-secret -n sdd-apps --docker-server="$REGISTRY" --docker-username=AWS --docker-password="$PASSWORD"` (all with `KUBECONFIG=/etc/kubernetes/admin.conf`).
- Make it executable (`chmod +x`).

**Edit B** — `terraform/environments/dev/main.tf`: add `null_resource.apply_ecr_pull_secret` (full HCL in spec §1.1). Placement: after `null_resource.apply_app_frontend_ingress`, before `set_node_provider_ids` — it only needs the `sdd-apps` namespace (`apply_app_infrastructure`), and nothing downstream depends on it.
- `depends_on = [null_resource.apply_app_infrastructure]`
- `triggers`: `ecr_repo_url = module.ecr.repository_urls["sdd-k8s-platform/frontend"]` (010) + `instance_id` (004-10 recreation re-apply)
- SSM command: `base64encode(replace(file("${path.module}/scripts/create-ecr-pull-secret.sh"), "%%ECR_REGISTRY%%", module.ecr.repository_urls["sdd-k8s-platform/frontend"]))` piped to `bash`
- `--comment "Create ECR pull secret in sdd-apps (011)"` (41 chars — under the 100-char SSM cap)
- SSM-agent wait loop, bootstrap-instance-id gate, and poll loop copied verbatim from `apply_app_backend`

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — no new AWS resources, no IAM.
- **Cluster Control Plane & Core Addons**: unchanged.
- **Platform Services**: unchanged (cert-manager, ingress-nginx).
- **Application Workloads**: unchanged (MySQL, app deployments, Ingress) — still on the public image baseline, no `imagePullSecrets`.
- **New artifact**: `ecr-pull-secret` (`kubernetes.io/dockerconfigjson`) in `sdd-apps` — the only cluster-side change.
- **Dependency Flow**: `apply_app_infrastructure` (creates `sdd-apps`, 004) → `apply_ecr_pull_secret` (this spec). Leaf — nothing depends on it. No cycle risk: it does not depend on `apply_aws_ccm` or `apply_cloudflare_record`.
- **Auth boundaries**: the ECR token is minted **on the control plane at runtime** (node role has `AmazonEC2ContainerRegistryReadOnly` → `ecr:GetAuthorizationToken`); it never appears in Terraform state or the SSM command document. Token valid ~12h — refresh by re-applying or re-running the script.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` (existing `terraform-apply.yml`, push to `main`) — creates `null_resource.apply_ecr_pull_secret`; the provisioner runs the SSM script on the control plane, which creates `ecr-pull-secret` in `sdd-apps`. Every existing resource no-ops.
2. **Stage 2 - Downstream (spec 012, after first real push)**: the manifest-swap spec adds `imagePullSecrets: [ecr-pull-secret]` + ECR image refs to `app-backend.yaml` / `app-frontend-ingress.yaml`, then proves the pull path with a live pod.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY the new `null_resource.apply_ecr_pull_secret`; zero changes to existing resources).
- **Secret Verification** (user-managed CLI): `kubectl get secret ecr-pull-secret -n sdd-apps -o jsonpath='{.type}'` → `kubernetes.io/dockerconfigjson`; decode `.data.\.dockerconfigjson` → `.auths` key = `<account_id>.dkr.ecr.us-east-1.amazonaws.com/sdd-k8s-platform/frontend`, username `AWS`.
- **No pull-path gate**: a real pull test is impossible until the first image is pushed — deferred to spec 012.
