# Architecture Delta: Flannel Per-Run Bootstrap Signal

**Branch**: `003-11-flannel-per-run-bootstrap-signal` | **Date**: 2026-09-09 | **Spec**: specs/003-11-flannel-per-run-bootstrap-signal/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | Publish the control plane's instance ID to `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` as the last step (per-run bootstrap-complete signal) |
| `terraform/environments/dev/main.tf` | Modify | Flannel gate: poll the instance-ID param until it equals the current control plane instance ID (replaces the "join-command param exists" wait) |
| `terraform/modules/worker-nodes/main.tf` | Modify | Change `user_data` from `file()` to `replace(file(...), "%%CONTROL_PLANE_INSTANCE_ID%%", var.control_plane_instance_id)` |
| `terraform/modules/worker-nodes/bootstrap.sh` | Modify | Add `%%CONTROL_PLANE_INSTANCE_ID%%` token; gate the join on the instance-ID param matching before fetching + `eval`ing the join command |

## 2. Architecture Delta

The bootstrap-complete signal changes from "the join-command parameter exists" to "the
bootstrap-instance-id parameter equals the current control plane instance ID".

- **Before**: the Flannel gate and worker bootstrap wait for the join-command param to *exist*.
  On a fresh apply the previous run's param still exists (stale, wrong IP) → the gate passes in
  ~10s → the Flannel command and worker join run against a not-ready / destroyed control plane.
- **After**: a new parameter holds the control plane's instance ID, published last in bootstrap.
  The gate waits for it to *equal* the current instance ID. A stale value (old instance ID) never
  matches, so a fresh apply blocks until the new bootstrap finishes; a persistent apply returns
  immediately. No delete, no race.

No resource graph changes. The SSM-agent wait (003-4), the `send-command`, the KUBECONFIG-prefixed
`kubectl apply` (003-9), and the status-poll query (003-10) are byte-for-byte unchanged. The
join-command parameter remains the join source; the instance-ID parameter is the freshness signal.

## 3. Rollout Stages

1. **Control-plane bootstrap (agent)** — add the instance-ID `put-parameter` as the last step.
2. **Flannel gate (agent)** — replace the join-command-exists wait with the instance-ID-equals wait.
3. **Worker bootstrap (agent)** — `replace()` token injection + instance-ID gate before `eval`.
4. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate`; grep
   gates (AC-002/AC-003/AC-004/AC-005); `terraform plan -detailed-exitcode` (AC-006).
5. **End-to-end verification (CI)** — apply runs; the gate blocks until the new control plane
   publishes its instance ID; the Flannel command succeeds; workers join; 3 nodes Ready (AC-007/AC-008).

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/control-plane/bootstrap.sh`
- **AC-003**: `grep -qF 'BOOTSTRAP_ID}" = "$${INSTANCE_ID}' terraform/environments/dev/main.tf`
- **AC-004**: `grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/worker-nodes/bootstrap.sh`
- **AC-005**: `grep -qF 'replace(file("${path.module}/bootstrap.sh")' terraform/modules/worker-nodes/main.tf`
- **AC-006**: `terraform plan -detailed-exitcode`
- **AC-007**: Flannel daemonset rolled out (SSM: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)
- **AC-008**: 3 nodes Ready (SSM: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers | grep -c ' Ready'` returns `3`)

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| The instance-ID param is stale from a previous run | The gate compares to the current instance ID; a stale value never matches |
| The `%%CONTROL_PLANE_INSTANCE_ID%%` token is not unique in the script | The token appears exactly once (line 14); `replace()` substitutes all occurrences, so even a duplicate would be harmless |
| Worker boots before the control plane publishes the signal | The 600s poll (same as the existing join-command poll) waits for it |
| The join command is stale when fetched | It is fetched only after the instance-ID gate passes; the control plane publishes the join command immediately before the instance-ID param in the same bootstrap |
| The node role lacks permission for the new param | The existing policy covers `parameter/sdd-k8s-platform/*` (cluster-plumbing line 123-124) — no IAM change needed |
