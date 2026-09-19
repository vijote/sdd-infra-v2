# Architecture Delta: letsencrypt-prod ACME Contact Email

**Branch**: `004-16-letsencrypt-contact-email` | **Date**: 2026-09-19 | **Spec**: [specs/004-16-letsencrypt-contact-email/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/cert-manager-issuers.yaml` | Modify | `letsencrypt-prod` `email` → `juanignaciodom3@gmail.com` (LE forbids the `example.com` placeholder) |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_cert_manager` — bump `cert_manager_ref` trigger so the SSM command re-runs with the updated manifest |

Two-file change. No module, IAM, or variable edits. The `selfsigned` ClusterIssuer and the SSM command (both commands, including the 004-15 retry loop) are unchanged.

### 1.1 Exact Edits

**Edit A** — `terraform/environments/dev/manifests/cert-manager-issuers.yaml` (line 20):
```yaml
# BEFORE:
    email: admin@example.com
# AFTER:
    email: juanignaciodom3@gmail.com
```
The `selfsigned` ClusterIssuer (lines 1–7) is untouched.

**Edit B** — `terraform/environments/dev/main.tf`, `null_resource.apply_cert_manager` (line 260):
```hcl
# BEFORE:
    cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry" # 004-13: ...; 004-14: ...; 004-15: retry ClusterIssuer apply (webhook startup race)
# AFTER:
    cert_manager_ref = "v1.19.4+webhook-gate+issuer-retry+issuer-email" # 004-13: ...; 004-14: ...; 004-15: retry ClusterIssuer apply (webhook startup race); 004-16: real ACME contact email (LE rejects example.com)
```
The provisioner command, `depends_on`, `instance_id` trigger, and `--comment` are untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: unchanged — no AWS resources, no IAM/IRSA/SG changes.
- **Cluster Control Plane & Core Addons**: unchanged.
- **Platform Services**: `cert-manager` (v1.19.4) — the only touched boundary. The `letsencrypt-prod` ClusterIssuer's ACME contact changes from a placeholder to a real email; cert-manager re-registers the ACME account in place.
- **Application Workloads**: unchanged (MySQL, app deployments, Ingress, the `demo-vijote-dev` Certificate).
- **Dependency Flow (unchanged)**: `apply_app_infrastructure` → `apply_cert_manager` → `apply_app_frontend_ingress`. This spec changes only the *manifest content* and the trigger of `apply_cert_manager`; its `depends_on` and downstream consumers are untouched.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` — the `cert_manager_ref` trigger bump marks `null_resource.apply_cert_manager` for replacement; all other resources are no-ops.
2. **Stage 2 - SSM Re-apply (in-place repair)**: the provisioner re-runs on the EXISTING control plane:
   - command[0]: `kubectl apply -f cert-manager.yaml` (idempotent) + `rollout status` for webhook + cainjector (gates retained from 004-14).
   - command[1]: ClusterIssuer apply (004-15 retry loop) — `kubectl apply` updates the `letsencrypt-prod` spec in place with the new email.
3. **Stage 3 - ACME re-registration + issuance (automatic)**: cert-manager detects the issuer spec change, re-registers the ACME account under `juanignaciodom3@gmail.com` (new key in the `letsencrypt-prod-account-key` secret; the `example.com` registration never succeeded, so nothing is lost), then processes the pending `demo-vijote-dev` Certificate: Order → HTTP-01 challenge (reachable — the Cloudflare CNAME is live per 009-2) → Let's Encrypt issues → the `demo-vijote-dev-tls` secret is populated → ingress-nginx serves the cert.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY `null_resource.apply_cert_manager` replacement).
- **Issuer Ready**: `kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True` (ACME account registered under the real email).
- **Certificate Ready**: `kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`.
- **End-to-end**: `curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'` → `200` and `curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'` → `200` (proves DNS + TLS + routing together; no nslookup per AGENTS.md).
