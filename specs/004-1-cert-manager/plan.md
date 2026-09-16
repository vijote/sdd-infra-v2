# Architecture Delta: cert-manager + Let's Encrypt (TLS Automation)

**Branch**: `004-1-cert-manager` | **Date**: 2026-09-16 | **Spec**: specs/004-1-cert-manager/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/manifests/cert-manager-issuers.yaml` | Create | `selfsigned` + `letsencrypt-prod` ClusterIssuers (base64-encoded into the SSM command; no `%%TOKEN%%` — no secrets) |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_cert_manager` — SSM Run Command on control plane: (1) `kubectl apply -f` upstream `cert-manager.yaml` v1.21.1, (2) `kubectl apply -f -` the issuers manifest |

**No new AWS resources.** cert-manager is a cluster-internal addon (no IRSA, no AWS API access). The only Terraform change is a `null_resource` that drives `kubectl` via SSM — identical in shape to `apply_app_infrastructure` / `apply_aws_ccm`.

## 2. Architectural Boundaries & Dependency Flow

- **Cluster Control Plane (existing)**: kubeadm 1.28.0, Flannel CNI, AWS EBS CSI, ingress-nginx `controller-v1.15.1` (installed by `apply_app_infrastructure`), AWS CCM (creates the public ALB).
- **Platform Services (this spec)**: cert-manager `v1.21.1` — controller + webhook + cainjector in `cert-manager` namespace; `selfsigned` ClusterIssuer (default, no DNS) and `letsencrypt-prod` ClusterIssuer (ACME HTTP-01, ingress class `nginx`).
- **Downstream Consumer (005)**: Ingress `tls` block + `Certificate` resource reference `selfsigned` (immediate dev TLS) or `letsencrypt-prod` (requires a live domain → the Route 53 work).
- **Dependency Flow**: `module.worker_nodes` → `apply_app_infrastructure` (ingress controller) → **`apply_cert_manager`** → (005) Ingress TLS.
- **Shared Constraints**: K8s 1.28.0; cert-manager pinned `v1.21.1`; all `kubectl` via SSM with `KUBECONFIG=/etc/kubernetes/admin.conf`; no IRSA.

## 3. Provisioning & Rollout Stages

1. **Stage 1 — Terraform IaC**: Add `null_resource.apply_cert_manager` to `dev/main.tf`. No AWS resource diff (pure `kubectl`-via-SSM). `terraform fmt -check -recursive && terraform validate` must pass.
2. **Stage 2 — SSM Apply (control plane)**: On `terraform apply`, the provisioner waits for SSM-agent registration + the `kubeadm-bootstrap-instance-id` gate (003-11), then sends one `AWS-RunShellScript`: apply upstream `cert-manager.yaml`, then apply the base64 issuers manifest. Poll `get-command-invocation` until `Success`.
3. **Stage 3 — Verification (user-managed)**: AC-003–AC-006 run on the control plane via SSM (controller/webhook/cainjector Ready, both ClusterIssuers present, 3 CRDs installed). Not added to `terraform-apply.yml` per P5/P6.

## 4. Implementation Notes (binding)

- **Match the existing `main.tf` pattern, not the spec's compact pseudo-HCL.** Use the verbose SSM block: `set -euo pipefail`, SSM-agent wait loop (30×10s), bootstrap-instance-id gate (60×10s), `send-command` with `--timeout-seconds 600` + `--comment`, then the `if [ "$STATUS" = "Success" ]` poll loop (60×10s). Copy the structure of `apply_app_infrastructure` (main.tf:169).
- **Triggers MUST include `instance_id`** (004-10 pattern) so the apply re-runs on cluster recreation, not only on a version bump:
  ```hcl
  triggers = {
    cert_manager_ref = "v1.21.1"
    instance_id      = module.control_plane.control_plane_instance_id
  }
  ```
- **`depends_on = [null_resource.apply_app_infrastructure]`** — cert-manager's HTTP-01 solver needs the ingress controller (installed there). The ALB (CCM) is only needed at *issuance* time (005), not install.
- **Placement**: insert the resource immediately after `apply_app_infrastructure` (main.tf:248) for dependency adjacency.
- **Upstream URL** (controller): `https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml`.
- **Issuers manifest**: local file, base64-encoded via `base64encode(file("${path.module}/manifests/cert-manager-issuers.yaml"))` — no `templatefile()` (no `${VAR}` in it), no `%%TOKEN%%` (no secrets).
- **Idempotency**: `kubectl apply` is re-runnable; the `null_resource` re-triggers only on `cert_manager_ref` or `instance_id` change.

## 5. Verification Gates

- **IaC (static, in `terraform-apply.yml`)**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002).
- **Cluster health (user-managed, via SSM)**:
  - AC-003: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager` (+ `-webhook`, `-cainjector`)
  - AC-004: `kubectl get clusterissuer selfsigned -o jsonpath={.metadata.name}` → `selfsigned`
  - AC-005: `kubectl get clusterissuer letsencrypt-prod -o jsonpath={.metadata.name}` → `letsencrypt-prod`
  - AC-006: `kubectl get crd certificates.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io -o name | wc -l` → `3`
- **Testing Policy**: No unit/E2E/CI validation generation (P6). AC-003–AC-006 are user-managed SSM checks defined in the spec, not added to workflows.
