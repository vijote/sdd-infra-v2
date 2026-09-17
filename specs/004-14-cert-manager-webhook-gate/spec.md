# Spec: cert-manager Webhook Readiness Gate

**Feature Branch**: `004-14-cert-manager-webhook-gate` | **Date**: 2026-09-16 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources) — SSM command + trigger change in the dev env
- **Kubernetes / Cluster Scope**: `cert-manager` namespace — webhook + cainjector Deployment readiness before ClusterIssuer apply
- **Target Services / Modules**: `null_resource.apply_cert_manager` (added by 004-1, pinned by 004-13)
- **Security & CI/CD**: unchanged (SSM Run Command apply pattern, no IRSA)

> **Root cause (004-1/004-13)**: `cert-manager.yaml` creates the `ValidatingWebhookConfiguration` (intercepts all ClusterIssuer/Issuer creates) in the SAME apply as the webhook Deployment. The second SSM command applies the ClusterIssuers ~1s later, but the `cert-manager-webhook` pod has not started listening yet → API server routes the ClusterIssuer create through the validating webhook → `dial tcp <pod-ip>:443: connect: connection refused` → apply fails. The v1.21.1 CRD failure (004-13) masked this race; once CRDs install cleanly, the webhook race is the next failure. **Fix**: gate the ClusterIssuer apply on `kubectl rollout status` of the webhook + cainjector Deployments.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# MODIFY existing null_resource.apply_cert_manager (004-1/004-13) in terraform/environments/dev/main.tf:
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers = {
    # 004-14: bump ref so the provisioner re-runs (command string is NOT in resource
    # state — a command-only edit would silently skip the re-apply on the live cluster).
    cert_manager_ref = "v1.19.4+webhook-gate" # was "v1.19.4"
    instance_id      = module.control_plane.control_plane_instance_id
  }
  # SSM command change: insert webhook + cainjector rollout gates BETWEEN the two applies:
  #   kubectl apply -f .../v1.19.4/cert-manager.yaml
  #     && kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s
  #     && kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s
  #   (then) base64 apply of manifests/cert-manager-issuers.yaml
}
```

### 1.2 Kubernetes Manifest Contracts
- **cert-manager** — static manifest `v1.19.4` (unchanged from 004-13).
- **ClusterIssuers** — `manifests/cert-manager-issuers.yaml` unchanged (`selfsigned` + `letsencrypt-prod`).
- **In-place repair**: the trigger bump re-runs the provisioner on the EXISTING cluster. `kubectl apply` is idempotent — re-applies the (already-present) cert-manager resources, waits for webhook + cainjector rollout, then applies the ClusterIssuers that the failed run left missing. No destroy/recreate.

### 1.3 Data & Storage Contracts
- None (no state change).

### 1.4 Network & Security Contracts
- Unchanged (no IRSA, no new SG rules).

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-006 are **user-managed SSM checks** (P5/P6) — `kubectl` prefixed with `KUBECONFIG=/etc/kubernetes/admin.conf`, executed via `aws ssm send-command` + poll.

- [ ] AC-001: Terraform syntax & formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [ ] AC-003: webhook + cainjector + controller Ready (the gate's precondition holds)
  ```bash
  kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s && kubectl wait --for=condition=Ready pod -l app=cert-manager-webhook -n cert-manager --timeout=300s && kubectl wait --for=condition=Ready pod -l app=cert-manager-cainjector -n cert-manager --timeout=300s
  ```
- [ ] AC-004: both ClusterIssuers present (the previously-failing step now succeeds)
  ```bash
  kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l  # → 2
  ```
- [ ] AC-005: both ClusterIssuers report `READY: True`
  ```bash
  kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
  ```
- [ ] AC-006: no `connection refused` / webhook error in the apply (the SSM command returns `Success`)
  ```bash
  # the apply_cert_manager SSM invocation Status == Success (no webhook dial error in StdErr)
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependency**: `004-13-cert-manager-k8s-version-skew` (cert-manager pinned to v1.19.4; CRDs install cleanly). This spec adds the readiness gate on top.
- **Trigger Bump Required**: the provisioner command string is NOT part of `null_resource` state (known gotcha) — a command-only edit would not re-run on the live cluster. The `cert_manager_ref` bump to `v1.19.4+webhook-gate` forces the re-apply.
- **Idempotency**: `kubectl apply` + `kubectl rollout status` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-006 are user-managed SSM checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
