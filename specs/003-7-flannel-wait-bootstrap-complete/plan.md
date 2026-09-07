# Architecture Delta: Flannel Wait Bootstrap Complete

**Branch**: `003-7-flannel-wait-bootstrap-complete` | **Date**: 2026-09-06 | **Spec**: specs/003-7-flannel-wait-bootstrap-complete/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | In `null_resource "apply_flannel_cni"`'s local-exec `command`: (1) at the start, `aws ssm delete-parameter --name /sdd-k8s-platform/kubeadm-join-command` to clear any stale signal from a previous run; (2) after the 003-4 SSM-agent wait, add a **bootstrap-complete wait** — poll `aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command` (60×10s) until the join command is published (control plane bootstrap finished), then `send-command` the Flannel apply |
| `terraform/modules/worker-nodes/bootstrap.sh` | Modify | Replace the single-shot `get-parameter` + `exit 1` with a poll loop (60×10s) that waits for the control plane to publish the join command before `eval`-ing it |

**No other files change.** The control plane bootstrap is **unchanged** (it already publishes the join command as its last step — the signal). The 003-4 SSM-agent wait, the `--parameters` JSON (003-6), the bash `interpreter` (003-5), the SSM send-command flags, and the existing invocation poll loop are byte-for-byte unchanged.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: The fix spans the dev-environment Terraform wiring (003-3's `null_resource "apply_flannel_cni"`) and the two node bootstraps — no resource change, no CloudFormation, no IAM change
- **Root cause (fatal)**: the Flannel command is sent at SSM-agent registration (~20s), but the control plane bootstrap takes several minutes (dnf install + `kubeadm init`). At 20s, `kubectl` is not installed, the API server is not up, and `/root/.kube/config` does not exist — so `kubectl apply -f /tmp/kube-flannel.yml` cannot succeed. The 10-min invocation poll times out.
- **Fix flow**:
  1. Flannel provisioner **deletes** the join-command parameter at the start of the apply (clears stale signal from a previous run) — done on the CI runner, which has the AWS CLI + SSM access immediately
  2. Control plane bootstrap **publishes** the join command at its **last step** (after `kubeadm init` + kubeconfig copy) — the bootstrap-complete signal
  3. Flannel provisioner waits for the SSM agent (003-4), **then** waits for the join-command parameter to exist (bootstrap complete), **then** sends the Flannel command — now `kubectl` is installed and the API server is up
  4. Worker bootstrap **polls** for the join command (instead of single-shot) so a worker that boots before the control plane finishes still joins once it's ready
- **Consumers**:
  - 003-3 AC-005/AC-006 verification → Flannel daemonset rolled out on the cluster
  - Downstream 003-3 worker pods depend on the CNI being present for pod networking
- **Instance re-launch**: changing the worker `user_data` changes the worker instance hash, so the workers are re-launched on the next apply — expected, no harm. The control plane bootstrap is unchanged, so the control plane is not re-launched by this spec (it is only re-launched if its own `user_data` or other instance attributes change)

## 3. Provisioning & Rollout Stages

- **Stage 1 — Edits (agent)**:
- Add the `delete-parameter` (stale-signal cleanup) + bootstrap-complete wait to the Flannel provisioner (`dev/main.tf`)
- Convert the worker bootstrap's single-shot fetch to a poll loop
- **Stage 2 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; the Flannel provisioner clears the stale parameter, waits for the control plane bootstrap to complete, then applies the Flannel CNI
- **Stage 3 — Unblocks 003-3**: the Flannel CNI daemonset is rolled out; AC-006 (daemonset rollout) is the end-to-end proof the Flannel command ran to completion after bootstrap

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -q 'kubeadm-join-command' terraform/environments/dev/main.tf`
- **AC-003**: `grep -q 'delete-parameter' terraform/environments/dev/main.tf`
- **AC-004**: `grep -q 'seq 1 60' terraform/modules/worker-nodes/bootstrap.sh`
- **AC-005**: `terraform plan -detailed-exitcode`
- **AC-006**: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

- **Stale signal**: without the provisioner's `delete-parameter`, a parameter left over from a previous run would make the Flannel gate pass immediately and re-introduce the race. Deleting from the provisioner (CI runner) at the start of the apply guarantees the parameter only exists for the current run's completed bootstrap
- **Why the provisioner deletes (not the control plane)**: the control plane bootstrap installs the AWS CLI at ~line 45, so it cannot clear a stale parameter before the Flannel provisioner's ~20-30s poll begins. The CI runner has the AWS CLI + SSM access immediately, so it is the right place to clear the stale signal
- **Worker single-shot → poll**: the worker's current single-shot `get-parameter` + `exit 1` would fail if the worker boots before the control plane finishes (the parameter is deleted by the Flannel provisioner and only re-created at the control plane bootstrap's end). Polling makes the worker wait for the control plane — the correct dependency
- **Instance re-launch**: changing the worker `user_data` re-launches the workers — expected, no harm; the join command is re-published by the control plane (unchanged)
- **CI runner SSM access**: the `delete-parameter` and `get-parameter` in the Flannel provisioner run on the GitHub Actions runner (PowerUserAccess role), which has `ssm:GetParameter` and `ssm:DeleteParameter` — no new IAM needed
- **Timeouts**: 60×10s = 600s (10 min) for bootstrap completion in both the Flannel provisioner and the worker bootstrap; `kubeadm init` on a t2.medium typically takes 2-4 min, so 10 min is generous
- **No resource impact**: provisioner + worker-bootstrap changes only; no instance type/subnet/IAM change, no state drift beyond the expected worker re-launch
- **Rollback**: revert both files and re-apply (re-introduces the Flannel/bootstrap race)
