---
name: 004-13-cert-manager-k8s-version-skew
description: Pin cert-manager from v1.21.1 to v1.19.4 because v1.20+ CRDs use selectableFields, which the K8s 1.28 API server rejects with a strict decoding error.
date: 2026-09-16
status: Implemented
---

# Spec: cert-manager K8s 1.28 Version Skew Fix

**Feature Branch**: `004-13-cert-manager-k8s-version-skew` | **Date**: 2026-09-16 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources) — single `null_resource` trigger + URL change in the dev env
- **Kubernetes / Cluster Scope**: `cert-manager` namespace — CRDs, controller/webhook/cainjector Deployments, ClusterIssuers
- **Target Services / Modules**: cert-manager pin `v1.21.1` → `v1.19.4`
- **Security & CI/CD**: unchanged (SSM Run Command apply pattern, no IRSA)

> **Root cause (004-1)**: cert-manager `v1.21.1` (and `v1.20.x`) CRDs carry `spec.versions[].selectableFields`, unknown to the K8s **1.28** API server → `strict decoding error: unknown field "spec.versions[0].selectableFields"` → CRD creation fails → webhook never Ready → ClusterIssuer applies fail with `connection refused`. Verified against release manifests: `v1.20.2` contains `selectableFields` (4 occurrences); `v1.19.4` does not (0). `v1.19.4` is the newest cert-manager compatible with K8s 1.28. Same bug class as `004-3-ebs-csi-k8s-version-skew` (addon version must match cluster minor).

### 1.1 Terraform / HCL Resource Contracts

```hcl
# MODIFY existing null_resource.apply_cert_manager (004-1) in terraform/environments/dev/main.tf:
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers = {
    cert_manager_ref = "v1.19.4" # was "v1.21.1" — v1.20+ CRDs require K8s 1.30+ (selectableFields)
    instance_id      = module.control_plane.control_plane_instance_id
  }
  # SSM command change: kubectl apply -f
  #   https://github.com/cert-manager/cert-manager/releases/download/v1.19.4/cert-manager.yaml
  #   (was .../v1.21.1/cert-manager.yaml); base64 apply of manifests/cert-manager-issuers.yaml unchanged
}
```

### 1.2 Kubernetes Manifest Contracts

- **cert-manager** — static manifest `v1.19.4` (6 CRDs: certificates, challenges, certificaterequests, clusterissuers, issuers, orders; controller + webhook + cainjector).
- **ClusterIssuers** — `manifests/cert-manager-issuers.yaml` unchanged (`selfsigned` + `letsencrypt-prod`).
- **In-place repair**: the trigger change re-runs the provisioner on the EXISTING cluster; `kubectl apply` is idempotent — updates the 2 CRDs partially created by the failed v1.21.1 run, creates the 4 missing, rolls Deployments to the v1.19.4 image, then applies the ClusterIssuers. No destroy/recreate.

### 1.3 Data & Storage Contracts
- None (no state change; cert-manager Secrets are created at issuance time, not install time).

### 1.4 Network & Security Contracts
- Unchanged (no IRSA, no new SG rules).

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-006 are **user-managed SSM checks** (P5/P6) — `kubectl` prefixed with `KUBECONFIG=/etc/kubernetes/admin.conf`, executed via `aws ssm send-command` + poll (same as 004-1).

- [ ] AC-001: Terraform syntax & formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [ ] AC-003: all 6 CRDs installed
  ```bash
  kubectl get crd certificates.cert-manager.io challenges.cert-manager.io certificaterequests.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io orders.cert-manager.io -o name | wc -l  # → 6
  ```
- [ ] AC-004: controller + webhook + cainjector Ready
  ```bash
  kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s && kubectl wait --for=condition=Ready pod -l app=cert-manager-webhook -n cert-manager --timeout=300s && kubectl wait --for=condition=Ready pod -l app=cert-manager-cainjector -n cert-manager --timeout=300s
  ```
- [ ] AC-005: both ClusterIssuers present
  ```bash
  kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l  # → 2
  ```
- [ ] AC-006: deployed image is v1.19.4
  ```bash
  kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q 'v1.19.4'
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependency**: `004-1-cert-manager` (the `apply_cert_manager` resource exists; the live cluster holds a partial v1.21.1 install that this spec repairs in place).
- **Version Selection**: `v1.19.4` = newest cert-manager whose release manifest contains zero `selectableFields` occurrences (verified by grep over release manifests: v1.20.2=4, v1.19.4=0).
- **Idempotency**: `kubectl apply` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-006 are user-managed SSM checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
