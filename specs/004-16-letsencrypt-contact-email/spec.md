---
name: 004-16-letsencrypt-contact-email
description: Replace the placeholder admin@example.com ACME contact on the letsencrypt-prod ClusterIssuer with a real email so Let's Encrypt accepts the account registration.
date: 2026-09-19
status: Implemented
---

# Spec: letsencrypt-prod ACME Contact Email

**Feature Branch**: `004-16-letsencrypt-contact-email` | **Date**: 2026-09-19 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources) — 1 manifest value + 1 trigger bump in the dev env
- **Kubernetes / Cluster Scope**: `cert-manager` — `letsencrypt-prod` ClusterIssuer ACME account re-registration
- **Target Services / Modules**: `manifests/cert-manager-issuers.yaml` (004-1) + `null_resource.apply_cert_manager` (004-1/004-13/004-14/004-15)
- **Security & CI/CD**: unchanged (SSM Run Command apply pattern, no IRSA)

> **Root cause (004-1 residual)**: the `letsencrypt-prod` ClusterIssuer was created with the placeholder ACME contact `email: admin@example.com` (004-1). The placeholder was inert until 009 made the issuer do real work: when the `demo-vijote-dev` Certificate requests issuance, cert-manager registers the ACME account with Let's Encrypt, which **rejects placeholder contact domains** — `400 urn:ietf:params:acme:error:invalidContact: contact email has forbidden domain "example.com"`. The issuer is stuck `Ready=False reason=ErrRegisterACMEAccount`, so no ACME Order/Challenge is ever created and the Certificate stays `Ready=False reason=DoesNotExist`. **Fix**: set a real contact email (`juanignaciodom3@gmail.com`) and re-apply the issuers. The email is a public ACME contact (expiry notices), not a secret — it lives in the manifest, not SSM.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# MODIFY null_resource.apply_cert_manager (004-1/004-13/004-14/004-15) in
# terraform/environments/dev/main.tf — trigger bump ONLY (the manifest is
# base64-embedded in the SSM command; the command string is NOT in resource
# state, so a manifest-only edit would silently skip the re-apply):
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers = {
    # 004-16: bump ref so the provisioner re-runs the ClusterIssuer apply.
    cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry+issuer-email" # was "v1.19.4+webhook-gate+issuer-retry"
    instance_id      = module.control_plane.control_plane_instance_id
  }
  # SSM command UNCHANGED (both commands, including the 004-15 retry loop).
}
```

### 1.2 Kubernetes Manifest Contracts

```yaml
# MODIFY manifests/cert-manager-issuers.yaml (004-1) — one value:
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: juanignaciodom3@gmail.com   # was admin@example.com (LE forbids placeholder domains)
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

- **`selfsigned` ClusterIssuer**: unchanged.
- **In-place repair**: the trigger bump re-runs the provisioner on the EXISTING cluster. `kubectl apply` updates the `letsencrypt-prod` spec in place; cert-manager detects the email change, re-registers the ACME account (new key in the `letsencrypt-prod-account-key` secret — the old `example.com` registration never succeeded, so nothing is lost), then proceeds: Order → HTTP-01 challenge → issue. The 004-15 retry loop is retained (harmless; the apply should succeed on attempt 1).
- **Rate limits**: a fresh ACME account has full production budget; no prior successful registrations exist to consume it.

### 1.3 Data & Storage Contracts
- None (no state change; the account key lives in the existing `letsencrypt-prod-account-key` secret, rotated in place).

### 1.4 Network & Security Contracts
- Unchanged (no IRSA, no new SG rules). The email is a public ACME contact, not a secret.

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-005 are **user-managed SSM checks** (P5/P6) — `kubectl` prefixed with `KUBECONFIG=/etc/kubernetes/admin.conf`, executed via `aws ssm send-command` + poll.

- [ ] AC-001: Terraform syntax & formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [ ] AC-003: `letsencrypt-prod` ClusterIssuer `READY: True` (ACME account registered under the real email)
  ```bash
  kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-004: `demo-vijote-dev` Certificate `Ready=True` (Order + HTTP-01 challenge completed, cert issued)
  ```bash
  kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-005: HTTPS serves frontend + backend (end-to-end: DNS + TLS + routing)
  ```bash
  curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'      # -> 200
  curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'   # -> 200
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-14` (webhook gate), `004-15` (issuer apply retry), `009-2` (Cloudflare CNAME live — the HTTP-01 challenge is reachable).
- **Trigger Bump Required**: the manifest is base64-embedded in the SSM command, and the command string is NOT part of `null_resource` state (known gotcha) — a manifest-only edit would not re-run on the live cluster. The `cert_manager_ref` bump forces the re-apply.
- **Email choice**: `juanignaciodom3@gmail.com` (user's personal email; receives Let's Encrypt expiry notices). Public ACME contact — not a secret, so it belongs in the manifest, not SSM.
- **Idempotency**: `kubectl apply` + `kubectl rollout status` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-005 are user-managed SSM checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
