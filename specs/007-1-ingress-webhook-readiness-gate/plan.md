# Architecture Delta: Ingress Webhook Readiness Gate

**Branch**: `007-1-ingress-webhook-readiness-gate` | **Date**: 2026-09-13 | **Spec**: [specs/007-1-ingress-webhook-readiness-gate/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/main.tf` | Modify | In `null_resource.apply_app_frontend_ingress`'s local-exec `command`: prepend `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s && ` to the SSM `--parameters` command string (line ~455). Nothing else changes. |

Single-file, single-line change. No new manifest, no module, no IAM, no `triggers`/`depends_on` change.

## 2. Key Design Decisions

### 2.1 In-command gate, not graph-level `depends_on`
The ingress-nginx controller is deployed by `apply_app_infrastructure` (004) — a different `null_resource` that runs earlier in the same apply. A `depends_on` edge would only order the *provisioner invocations*; 004's provisioner returns as soon as its `kubectl apply` finishes, not when the controller is Ready. The readiness wait must therefore live **inside** 007's SSM command, on the control plane, where the API server is reachable.

### 2.2 `kubectl rollout status` as the gate
- Blocks until the controller pod is **Ready** (readiness probe passing ⇒ controller listening on :8443 ⇒ `ingress-nginx-controller-admission` Service endpoints populated ⇒ the validating webhook is reachable).
- `--timeout=300s` matches the 004-4 CCM rollout-wait pattern; fits inside the existing `--timeout-seconds 600` SSM command timeout (300s gate + apply ≪ 600s).
- Idempotent: on a persistent cluster where the controller is already rolled out, it returns immediately — zero added latency to steady-state applies.

### 2.3 Re-run mechanism (003-6)
Changing the `command` string changes the provisioner's computed configuration → Terraform re-runs `apply_app_frontend_ingress` on the next apply. The SSM command is re-issued; `kubectl apply` is idempotent (Deployment/Service report `unchanged`, the previously-failed Ingress is created). No `triggers` bump needed.

### 2.4 Root cause (verified 2026-09-13)
Fresh-cluster sequence: controller pod fails sandbox creation (Flannel race: `open /run/flannel/subnet.env: no such file or directory`) → kubelet retries → controller eventually Ready. 007's apply ran in that window: admission Service had **no endpoints** → API server webhook call `dial tcp 192.168.1.10:443: connect: connection refused` → Ingress creation failed (Deployment/Service created fine) → SSM `Failed` → provisioner exit 1 → `apply_aws_ccm` (004-4) blocked by `depends_on`.

## 3. SSM Command Flow (local-exec, after change)

Single `&&`-chained command on the control plane (gated on SSM-agent registration + `kubeadm-bootstrap-instance-id`, per 003 pattern — unchanged):

1. `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s`  ← **new gate**
2. `echo '<base64 app-frontend-ingress.yaml, %%INGRESS_HOST%% replaced>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -`

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show ONLY the `apply_app_frontend_ingress` re-run (AC-001/AC-002)
- **Command Validation**: `terraform plan -no-color | grep -c 'rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s'` returns `1` (AC-003)
- **Ingress Verification**: `kubectl get ingress -n sdd-apps app-ingress` + host/paths jsonpath (AC-004/AC-005)
- **Rollout Verification**: `kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=300s` (AC-006)
- **Webhook Verification**: `kubectl get endpoints ingress-nginx-controller-admission -n ingress-nginx` non-empty (AC-007)

## 5. Risks / Notes

- **No collateral plan changes**: the only config delta is the `command` string of one `null_resource`; all other resources (VPC, IAM, control plane, workers, prior null_resources) are untouched.
- **Downstream unblock**: once this apply succeeds, `apply_aws_ccm` (004-4) runs — its T004–T007 verification gates (EXTERNAL-IP, Ingress ADDRESS, public-subnet annotation) become verifiable in the same or next CI run.
- **Flannel race not fixed here**: transient by design (kubelet retries succeed); the gate makes 007 tolerant of it. A structural Flannel fix would be a separate spec if it ever becomes non-transient.
