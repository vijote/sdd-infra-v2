# Architecture Delta: cert-manager ClusterIssuer Apply Retry

**Branch**: `004-15-cert-manager-issuer-apply-retry` | **Date**: 2026-09-17 | **Spec**: [specs/004-15-cert-manager-issuer-apply-retry/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_cert_manager` — bump `cert_manager_ref` trigger + wrap SSM command[1] (ClusterIssuer apply) in a bounded retry loop |

Single-file change. No module, manifest, or variable edits. `manifests/cert-manager-issuers.yaml` and the cert-manager v1.19.4 manifest are unchanged.

### 1.1 Exact Edit (the only change)

`null_resource.apply_cert_manager` (dev `main.tf`, ~line 256):

1. **Trigger bump** (forces the provisioner to re-run on the live cluster — the command string is NOT in `null_resource` state):
   ```hcl
   cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry" # was "v1.19.4+webhook-gate"
   ```

2. **SSM command[1] retry wrap** — command[0] (apply cert-manager.yaml + webhook + cainjector rollout gates) is UNCHANGED. command[1] changes from a single `kubectl apply` to a bounded retry loop. In the Terraform heredoc, the shell loop variable is written `$${i}` (Terraform escapes a literal `$` as `$${`); the base64 manifest is still interpolated by Terraform via `${base64encode(file(...))}`:
   ```
   # BEFORE (command[1]):
   \"echo '<b64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\"

   # AFTER (command[1]):
   \"for i in $(seq 1 10); do if echo '<b64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -; then echo \"ClusterIssuers applied successfully\"; exit 0; fi; echo \"ClusterIssuer apply attempt $${i} failed, retrying in 5s\" >&2; sleep 5; done; echo \"ClusterIssuer apply failed after 10 attempts\" >&2; exit 1\"
   ```
   - `<b64>` = `${base64encode(file("${path.module}/manifests/cert-manager-issuers.yaml"))}` (unchanged interpolation).
   - `$(seq 1 10)` is a shell command substitution — passes through the heredoc literally (Terraform only interpolates `${...}`, not `$(`).
   - `exit 0` on first success; `exit 1` after the 10th failed attempt. Each `commands[]` element is a separate SSM shell, so `exit` scopes to command[1] (the last command).
   - `--timeout-seconds 600` and `--comment` unchanged.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — no AWS resources, no IAM/IRSA/SG changes.
- **Cluster Control Plane & Core Addons**: unchanged (kubeadm, Flannel, EBS CSI).
- **Platform Services**: `cert-manager` (v1.19.4) — the only touched boundary. The `apply_cert_manager` SSM command now tolerates the transient webhook startup race on a fresh cluster.
- **Application Workloads**: unchanged (MySQL, app deployments, Ingress).
- **Dependency Flow (unchanged)**: `apply_app_infrastructure` → `apply_cert_manager` → `apply_app_frontend_ingress`. This spec changes only the *internal* SSM command of `apply_cert_manager`; its `depends_on` and downstream consumers are untouched.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` — the `cert_manager_ref` trigger bump marks `null_resource.apply_cert_manager` for replacement; all other resources are no-ops.
2. **Stage 2 - SSM Re-apply (in-place repair)**: the provisioner re-runs on the EXISTING control plane:
   - command[0]: `kubectl apply -f cert-manager.yaml` (idempotent) + `rollout status` for webhook + cainjector (gates retained from 004-14).
   - command[1]: ClusterIssuer apply wrapped in the 10×5s retry loop — a transient `connection refused` self-heals on a subsequent attempt.
3. **Stage 3 - Downstream (unchanged)**: `apply_app_frontend_ingress` proceeds once `apply_cert_manager` succeeds; the `demo-vijote-dev` Certificate then issues via `letsencrypt-prod` (009).

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY `null_resource.apply_cert_manager` replacement).
- **SSM Invocation**: `aws ssm get-command-invocation --instance-id <cp> --command-id <cmd> --query 'CommandInvocation.Status' --output text` → `Success` (no `connection refused` in StdErr).
- **ClusterIssuer Presence**: `kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`.
- **ClusterIssuer Ready**: `kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'` → both `True`.
- **Webhook Round-Trip**: `kubectl get clusterissuers >/dev/null && echo "webhook OK"` → `webhook OK` (proves the validating webhook serves — the race window is closed).
