# Execution Graph (DAG): letsencrypt-prod ACME Contact Email

**Input**: Design documents from `/specs/004-16-letsencrypt-contact-email/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks (parallel) + 3 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Manifest] In `terraform/environments/dev/manifests/cert-manager-issuers.yaml`, the `letsencrypt-prod` ClusterIssuer (004-1): change `email: admin@example.com` → `email: juanignaciodom3@gmail.com` (Let's Encrypt rejects placeholder contact domains — `400 invalidContact: contact email has forbidden domain "example.com"` — which left the issuer stuck at `Ready=False reason=ErrRegisterACMEAccount` and blocked the `demo-vijote-dev` Certificate). Do NOT touch: the `selfsigned` ClusterIssuer, the `server`, `privateKeySecretRef`, or the `http01` solver
- [x] T002 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager` (004-1/004-13/004-14/004-15): bump `triggers.cert_manager_ref` `"v1.19.4+webhook-gate+issuer-retry"` → `"v1.19.4+webhook-gate+issuer-retry+issuer-email"` and append `; 004-16: real ACME contact email (LE rejects example.com)` to the trailing comment. The manifest is base64-embedded in the SSM command and the command string is NOT in `null_resource` state, so the bump forces the re-apply. Do NOT touch: the provisioner command (both SSM commands, including the 004-15 retry loop), `depends_on`, `instance_id` trigger, or `--comment`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [ ] T004 [Stage 2: Verify] AC-003: `kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True` (ACME account registered under the real email; no `ErrRegisterACMEAccount`)
- [ ] T005 [Stage 2: Verify] AC-004/AC-005: (1) `kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`, (2) `curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'` → `200` AND `curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'` → `200` (proves DNS + TLS + routing end-to-end; no nslookup per AGENTS.md)
