# Architecture Delta: cert-manager Webhook Readiness Gate

**Branch**: `004-14-cert-manager-webhook-gate` | **Date**: 2026-09-16 | **Spec**: specs/004-14-cert-manager-webhook-gate/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/main.tf` | Modify | In `null_resource.apply_cert_manager` (004-1/004-13): (1) `triggers.cert_manager_ref` `"v1.19.4"` → `"v1.19.4+webhook-gate"` (forces re-apply — command string is NOT in null_resource state), (2) SSM first command: append `&& KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s` after the `kubectl apply -f .../v1.19.4/cert-manager.yaml`, (3) `--comment` → `"Deploy cert-manager v1.19.4 + webhook gate + ClusterIssuers (004-1/004-13/004-14)"` |

**Single file, 3 changes.** No new resources, no manifest changes, no AWS diff. `manifests/cert-manager-issuers.yaml` untouched.

## 2. Architectural Boundaries & Dependency Flow

- **Unchanged boundaries**: VPC, IAM, EC2, CNI, EBS CSI, ingress-nginx, CCM, MySQL, app workloads.
- **Changed component**: `apply_cert_manager` SSM command — inserts a webhook + cainjector rollout gate between the cert-manager manifest apply and the ClusterIssuer apply.
- **Dependency Flow (unchanged)**: `module.worker_nodes` → `apply_app_infrastructure` → `apply_cert_manager` → (005) Ingress TLS.
- **Precedent**: `007-1-ingress-webhook-readiness-gate` (same pattern: gate Ingress applies on ingress-nginx-controller rollout).

## 3. Provisioning & Rollout Stages

1. **Stage 1 — Terraform IaC**: Edit the 3 items in `apply_cert_manager`. `terraform fmt -check -recursive && terraform validate` must pass. Plan delta = exactly 1 `null_resource` replacement (trigger change).
2. **Stage 2 — SSM Apply (control plane, in-place repair)**: On `terraform apply`, the trigger bump re-runs the provisioner against the EXISTING cluster. Idempotent `kubectl apply` of the v1.19.4 manifest (resources already present → no-op), then `rollout status` waits for webhook + cainjector to be Ready, then applies the ClusterIssuers (the step that previously failed). No destroy/recreate.
3. **Stage 3 — Verification (user-managed)**: AC-003–AC-006 via SSM (pods Ready, 2 ClusterIssuers, READY=True, SSM Status=Success). Not added to `terraform-apply.yml` per P5/P6.

## 4. Implementation Notes (binding)

- **Exact edit locations** in `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager`:
  - `triggers` block: `cert_manager_ref = "v1.19.4"` → `cert_manager_ref = "v1.19.4+webhook-gate"` (update the `# 004-13` comment to note 004-14's gate).
  - SSM `--parameters` first command: the current single `kubectl apply -f .../v1.19.4/cert-manager.yaml` becomes a `&&`-chained sequence: apply → `rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s` → `rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s`. Each `kubectl` keeps the `KUBECONFIG=/etc/kubernetes/admin.conf` prefix.
  - `--comment` → `"Deploy cert-manager v1.19.4 + webhook gate + ClusterIssuers (004-1/004-13/004-14)"`.
- **Do NOT touch**: the second SSM command (base64 issuers apply), the SSM-agent wait loop, the bootstrap-instance-id gate, the poll loop, `depends_on`, or `instance_id` trigger.
- **Do NOT edit** `specs/004-1-cert-manager/`, `specs/004-13-*/` files, or `manifests/cert-manager-issuers.yaml` (follow-on spec convention: fix lives in 004-14).
- **Idempotency**: `kubectl apply` + `kubectl rollout status` re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.

## 5. Verification Gates

- **IaC (static, in `terraform-apply.yml`)**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002 — plan delta = 1 null_resource replacement only).
- **Cluster health (user-managed, via SSM, `KUBECONFIG=/etc/kubernetes/admin.conf`)**:
  - AC-003: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s` (+ `-webhook`, `-cainjector`)
  - AC-004: `kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`
  - AC-005: `kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'` → both `True`
  - AC-006: the `apply_cert_manager` SSM invocation `Status == Success` (no webhook `connection refused` in StdErr)
- **Testing Policy**: No unit/E2E/CI validation generation (P6). AC-003–AC-006 are user-managed SSM checks, not added to workflows.
