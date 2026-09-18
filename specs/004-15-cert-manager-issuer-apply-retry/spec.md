# Spec: cert-manager ClusterIssuer Apply Retry

**Feature Branch**: `004-15-cert-manager-issuer-apply-retry` | **Date**: 2026-09-17 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources) — SSM command + trigger change in the dev env
- **Kubernetes / Cluster Scope**: `cert-manager` namespace — ClusterIssuer apply hardened against the webhook startup race
- **Target Services / Modules**: `null_resource.apply_cert_manager` (added by 004-1, pinned by 004-13, gated by 004-14)
- **Security & CI/CD**: unchanged (SSM Run Command apply pattern, no IRSA)

> **Root cause (004-14 residual)**: 004-14 gates the ClusterIssuer apply on `kubectl rollout status` of the webhook + cainjector Deployments. `rollout status` proves the webhook pod was **Ready** at the moment it checked, but on a **fresh cluster** there is a short window where the pod's endpoint is programmed into kube-proxy (so the API server's DNAT to the pod exists → a TCP **RST / `connection refused`**, not a timeout) while the webhook's full serving path is not yet consistently accepting connections. The ClusterIssuer create is intercepted by the `webhook.cert-manager.io` **validating** webhook → `dial tcp <cluster-ip>:443: connect: connection refused` → the second SSM command fails. The pods are healthy afterward (0 restarts, Ready, clean logs) — the failure is a **transient startup/propagation race**, not a config bug. **Fix**: wrap the ClusterIssuer apply in a bounded retry loop so the apply lands after the race window.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# MODIFY existing null_resource.apply_cert_manager (004-1/004-13/004-14) in terraform/environments/dev/main.tf:
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers = {
    # 004-15: bump ref so the provisioner re-runs (command string is NOT in resource
    # state — a command-only edit would silently skip the re-apply on the live cluster).
    cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry" # was "v1.19.4+webhook-gate"
    instance_id      = module.control_plane.control_plane_instance_id
  }
  # SSM command: command[0] UNCHANGED (apply cert-manager.yaml + webhook + cainjector
  # rollout gates). command[1] CHANGED: the base64 ClusterIssuer apply is wrapped in a
  # bounded retry loop (10 attempts x 5s) so a transient webhook `connection refused`
  # self-heals instead of failing the whole apply:
  #   for i in $(seq 1 10); do
  #     if echo '<b64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -; then
  #       echo "ClusterIssuers applied successfully"; exit 0
  #     fi
  #     echo "ClusterIssuer apply attempt $i failed, retrying in 5s" >&2; sleep 5
  #   done
  #   echo "ClusterIssuer apply failed after 10 attempts" >&2; exit 1
}
```

### 1.2 Kubernetes Manifest Contracts
- **cert-manager** — static manifest `v1.19.4` (unchanged from 004-13).
- **ClusterIssuers** — `manifests/cert-manager-issuers.yaml` unchanged (`selfsigned` + `letsencrypt-prod`).
- **In-place repair**: the trigger bump re-runs the provisioner on the EXISTING cluster. `kubectl apply` is idempotent — re-applies the (already-present) cert-manager resources, waits for webhook + cainjector rollout, then applies the ClusterIssuers (with retry) that the failed run left missing. No destroy/recreate.

### 1.3 Data & Storage Contracts
- None (no state change).

### 1.4 Network & Security Contracts
- Unchanged (no IRSA, no new SG rules).

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-006 are **user-managed SSM checks** (P5/P6) — `kubectl` prefixed with `KUBECONFIG=/etc/kubernetes/admin.conf`, executed via `aws ssm send-command` + poll.

- [ ] AC-001: Terraform syntax & formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [ ] AC-003: both ClusterIssuers present (the previously-failing step now succeeds)
  ```bash
  kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l  # → 2
  ```
- [ ] AC-004: both ClusterIssuers report `READY: True`
  ```bash
  kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
  ```
- [ ] AC-005: the `apply_cert_manager` SSM invocation returns `Success` (no `connection refused` / webhook dial error in StdErr)
  ```bash
  # aws ssm get-command-invocation --instance-id <cp> --command-id <cmd> --query 'CommandInvocation.Status' --output text  # → Success
  ```
- [ ] AC-006: the webhook is callable (a real validating round-trip succeeds — proves the race window is closed)
  ```bash
  kubectl get clusterissuers >/dev/null && echo "webhook OK"  # → webhook OK
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependency**: `004-14-cert-manager-webhook-gate` (webhook + cainjector rollout gate already in place). This spec adds the retry on top; the rollout gate is retained.
- **Trigger Bump Required**: the provisioner command string is NOT part of `null_resource` state (known gotcha) — a command-only edit would not re-run on the live cluster. The `cert_manager_ref` bump to `v1.19.4+webhook-gate+issuer-retry` forces the re-apply.
- **Retry Bounds**: 10 attempts x 5s = up to ~50s of retry; the webhook is healthy, so the first or second attempt lands after the race window. `exit 0` on first success, `exit 1` after the final attempt.
- **Idempotency**: `kubectl apply` + `kubectl rollout status` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-006 are user-managed SSM checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
