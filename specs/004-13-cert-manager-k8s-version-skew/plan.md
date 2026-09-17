# Architecture Delta: cert-manager K8s 1.28 Version Skew Fix

**Branch**: `004-13-cert-manager-k8s-version-skew` | **Date**: 2026-09-16 | **Spec**: specs/004-13-cert-manager-k8s-version-skew/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | In `null_resource.apply_cert_manager` (added by 004-1): (1) `triggers.cert_manager_ref` `"v1.21.1"` → `"v1.19.4"`, (2) SSM command URL `.../releases/download/v1.21.1/cert-manager.yaml` → `.../releases/download/v1.19.4/cert-manager.yaml`, (3) `--comment` version string `v1.21.1` → `v1.19.4` |

**Single file, 3 string changes.** No new resources, no manifest changes, no AWS diff. `manifests/cert-manager-issuers.yaml` is untouched (ClusterIssuers are version-agnostic to this fix).

## 2. Architectural Boundaries & Dependency Flow

- **Unchanged boundaries**: VPC, IAM, EC2, CNI, EBS CSI, ingress-nginx, CCM, MySQL, app workloads — all untouched.
- **Changed component**: cert-manager addon pin `v1.21.1` → `v1.19.4` (newest release whose CRDs decode on K8s 1.28; `selectableFields` absent).
- **Dependency Flow (unchanged)**: `module.worker_nodes` → `apply_app_infrastructure` → `apply_cert_manager` → (005) Ingress TLS.
- **Precedent**: `004-3-ebs-csi-k8s-version-skew` — addon minor version must match cluster K8s minor (1.28).

## 3. Provisioning & Rollout Stages

1. **Stage 1 — Terraform IaC**: Edit the 3 strings in `apply_cert_manager`. `terraform fmt -check -recursive && terraform validate` must pass. Plan delta = exactly 1 `null_resource` replacement (trigger change).
2. **Stage 2 — SSM Apply (control plane, in-place repair)**: On `terraform apply`, the changed trigger re-runs the provisioner against the EXISTING cluster. Idempotent `kubectl apply` of the v1.19.4 manifest: updates the 2 CRDs partially created by the failed v1.21.1 run, creates the 4 missing CRDs, rolls controller/webhook/cainjector Deployments to the v1.19.4 image, then applies the (unchanged) ClusterIssuers. No destroy/recreate.
3. **Stage 3 — Verification (user-managed)**: AC-003–AC-006 via SSM (6 CRDs, pods Ready, 2 ClusterIssuers, image tag v1.19.4). Not added to `terraform-apply.yml` per P5/P6.

## 4. Implementation Notes (binding)

- **Exact edit locations** in `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager` (004-1):
  - `triggers` block: `cert_manager_ref = "v1.21.1"` → `cert_manager_ref = "v1.19.4"` (keep the `# 004-10` comment on the `instance_id` line; add a `# 004-13: v1.20+ CRDs require K8s 1.30+ (selectableFields)` note on the ref line).
  - SSM `--parameters` first command: `https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml` → `.../v1.19.4/cert-manager.yaml`.
  - `--comment "Deploy cert-manager v1.21.1 + ClusterIssuers (004-1)"` → `--comment "Deploy cert-manager v1.19.4 + ClusterIssuers (004-1/004-13)"`.
- **Do NOT touch**: the second SSM command (base64 issuers apply), the SSM-agent wait loop, the bootstrap-instance-id gate, the poll loop, `depends_on`, or `instance_id` trigger.
- **Do NOT edit** `specs/004-1-cert-manager/` files or `manifests/cert-manager-issuers.yaml` (follow-on spec convention: fix lives in 004-13).
- **Idempotency**: `kubectl apply` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.

## 5. Verification Gates

- **IaC (static, in `terraform-apply.yml`)**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002 — plan delta = 1 null_resource replacement only).
- **Cluster health (user-managed, via SSM, `KUBECONFIG=/etc/kubernetes/admin.conf`)**:
  - AC-003: `kubectl get crd certificates.cert-manager.io challenges.cert-manager.io certificaterequests.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io orders.cert-manager.io -o name | wc -l` → `6`
  - AC-004: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s` (+ `-webhook`, `-cainjector`)
  - AC-005: `kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`
  - AC-006: `kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'` contains `v1.19.4`
- **Testing Policy**: No unit/E2E/CI validation generation (P6). AC-003–AC-006 are user-managed SSM checks, not added to workflows.
