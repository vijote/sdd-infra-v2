# Spec: Flannel Wait Bootstrap Complete

**Feature Branch**: `003-7-flannel-wait-bootstrap-complete` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner + bootstrap script corrections only — no new AWS resources, no resource changes
- **Kubernetes / Cluster Scope**: Worker nodes module (003-3-worker-nodes) — Flannel CNI application step; control plane + worker bootstrap
- **Target Services**:
  - `terraform/environments/dev/main.tf` (`null_resource "apply_flannel_cni"` local-exec provisioner)
  - `terraform/modules/control-plane/bootstrap.sh` (join-command SSM parameter lifecycle)
  - `terraform/modules/worker-nodes/bootstrap.sh` (join-command fetch)
- **Root Cause (fatal)**: `terraform apply` fails with `Flannel CNI apply timed out waiting for invocation` (10-min poll timeout). The SSM agent registers at ~20s (003-4 fix works), so `send-command` fires at ~20s — but the control plane's bootstrap takes **several minutes** (dnf install of containerd + kubelet/kubeadm/kubectl, then `kubeadm init`). At 20s: `kubectl` is **not installed**, the API server is **not up**, and `/root/.kube/config` **does not exist** (copied only after `kubeadm init` succeeds). So `kubectl apply -f /tmp/kube-flannel.yml` cannot succeed — the Flannel command races against the bootstrap.
- **Decision**: Gate the Flannel command on **bootstrap completion**, not SSM-agent registration. The control plane bootstrap publishes the join command to SSM (`/sdd-k8s-platform/kubeadm-join-command`) as its **last step** (after `kubeadm init` + kubeconfig copy) — a reliable "bootstrap complete" signal. The Flannel provisioner waits for that parameter to exist (via `aws ssm get-parameter` from the CI runner) before sending the Flannel command.

### 1.1 Bootstrap-Complete Signal Contract

The join-command SSM parameter is the bootstrap-complete signal. To make it a reliable **per-run** signal (not stale from a previous run), its lifecycle is:

| Phase | Action | Where |
|-------|--------|-------|
| Flannel provisioner start | `aws ssm delete-parameter --name <param>` (ignore "not found") — clears stale signal from a previous run | `dev/main.tf` provisioner (new, before the SSM-agent wait) |
| Bootstrap end | `aws ssm put-parameter --name <param> --type SecureString --value <join-cmd> --overwrite` (existing) | `control-plane/bootstrap.sh` (last step) |
| Worker join | **Poll** `aws ssm get-parameter` until the parameter exists (replaces single-shot fetch) | `worker-nodes/bootstrap.sh` |
| Flannel gate | **Poll** `aws ssm get-parameter` (from CI runner) until the parameter exists, then `send-command` | `dev/main.tf` provisioner |

- **Why the Flannel provisioner deletes (not the control plane)**: the control plane bootstrap installs the AWS CLI at ~line 45, so the earliest it can delete the parameter is ~60-120s after launch. But the Flannel provisioner starts polling at ~20-30s (right after the SSM agent registers). If a **stale** parameter from a previous run exists, the Flannel provisioner would see it at ~20-30s, *before* the control plane deletes it at ~60-120s → thinks bootstrap is complete → sends the Flannel command → fails. Deleting from the Flannel provisioner (CI runner, which has the AWS CLI + SSM access) at ~20-30s closes this race: the stale parameter is cleared before the poll begins, and the parameter only re-appears when the control plane bootstrap completes.
- **Why the worker must poll**: the worker's current single-shot `get-parameter` + `exit 1` would fail if the worker boots before the control plane finishes (the parameter is deleted by the Flannel provisioner and only re-created at the control plane bootstrap's end). Polling makes the worker wait for the control plane, which is the correct dependency.
- **Parameter name**: `/sdd-k8s-platform/kubeadm-join-command` (unchanged; already defined in both bootstraps as `SSM_PARAM_NAME`).

### 1.2 Terraform Provisioner Command Contract

File: `terraform/environments/dev/main.tf`

**Before (broken — Flannel command sent at SSM-agent registration, ~20s, before bootstrap completes):**

```hcl
      # Wait for the control plane's SSM agent to register ...
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information ...) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then break; fi
        sleep 10
      done
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        # ... (curl + kubectl apply — fails: kubectl not installed, API server not up)
```

**After (fixed — clear stale signal, wait for bootstrap-complete signal, then send):**

```hcl
      # Clear any stale join-command parameter from a previous run so its presence
      # is a reliable per-run "bootstrap complete" signal (deleted here, re-created
      # by the control plane bootstrap at its end after kubeadm init).
      aws ssm delete-parameter \
        --name "/sdd-k8s-platform/kubeadm-join-command" 2>/dev/null || true
      # Wait for the control plane's SSM agent to register (003-4 — keep) ...
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information ...) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then break; fi
        sleep 10
      done
      # Wait for bootstrap completion: the join-command parameter is published by
      # the control plane bootstrap as its LAST step (after kubeadm init + kubeconfig).
      # It was deleted above, so its presence means THIS run's bootstrap finished
      # and kubectl + the API server are ready.
      for i in $(seq 1 60); do
        JOIN_PRESENT=$(aws ssm get-parameter \
          --name "/sdd-k8s-platform/kubeadm-join-command" \
          --with-decryption \
          --query 'Parameter.Value' --output text 2>/dev/null) || JOIN_PRESENT=""
        if [ -n "$${JOIN_PRESENT}" ]; then
          echo "Control plane bootstrap complete (join command published)"
          break
        fi
        sleep 10
      done
      if [ -z "$${JOIN_PRESENT}" ]; then
        echo "Control plane bootstrap did not complete within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        # ... (curl + kubectl apply — now succeeds: kubectl installed, API server up)
```

- **Three steps, in order**: (1) `delete-parameter` clears the stale signal, (2) the 003-4 SSM-agent wait (so `send-command` doesn't hit `InvalidInstanceId`), (3) the new bootstrap-complete wait (so `kubectl apply` doesn't race `kubeadm init`). The agent registers in ~20s; bootstrap completion takes several minutes.
- **Timeout**: 60 iterations × 10s = 600s (10 min) for bootstrap completion. `kubeadm init` on a t2.medium typically takes 2-4 min; 10 min is generous.
- **CI runner SSM access**: the `delete-parameter` and `get-parameter` run on the GitHub Actions runner (the `local-exec` provisioner), which assumes the `github-actions-assume-role` (PowerUserAccess) — it has `ssm:GetParameter` and `ssm:DeleteParameter`. No new IAM needed.

### 1.3 Control Plane Bootstrap Contract

File: `terraform/modules/control-plane/bootstrap.sh`

**No change.** The control plane bootstrap already publishes the join command as its **last step** (after `kubeadm init` + kubeconfig copy) — that is the bootstrap-complete signal. The stale-signal cleanup (`delete-parameter`) is done by the Flannel provisioner (CI runner) at the start of the apply, **not** by the control plane bootstrap, because the control plane only installs the AWS CLI at ~line 45 (too late to clear a stale parameter before the Flannel provisioner's ~20-30s poll begins).

- The existing `put-parameter` at the end is **unchanged** and is the signal the Flannel provisioner and worker bootstrap wait for.

### 1.4 Worker Bootstrap Contract

File: `terraform/modules/worker-nodes/bootstrap.sh`

**Before (broken — single-shot fetch, fails if worker boots before control plane finishes):**

```bash
JOIN_COMMAND=$(aws ssm get-parameter \
  --name "${SSM_PARAM_NAME}" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)
if [ -z "${JOIN_COMMAND}" ]; then
  echo "ERROR: join command not found in SSM ${SSM_PARAM_NAME}" >&2
  exit 1
fi
eval "${JOIN_COMMAND}"
```

**After (fixed — poll until the control plane publishes the join command):**

```bash
# --- Fetch the join command from SSM (SecureString) and join the cluster.
# --- Poll: the Flannel provisioner deletes the parameter at the start of the
# --- apply and the control plane re-creates it at bootstrap end, so it may not
# --- exist yet when a worker boots. Wait up to 10 min for the control plane to
# --- finish kubeadm init. ---
JOIN_COMMAND=""
for i in $(seq 1 60); do
  JOIN_COMMAND=$(aws ssm get-parameter \
    --name "${SSM_PARAM_NAME}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null) || JOIN_COMMAND=""
  if [ -n "${JOIN_COMMAND}" ]; then
    break
  fi
  sleep 10
done
if [ -z "${JOIN_COMMAND}" ]; then
  echo "ERROR: join command not found in SSM ${SSM_PARAM_NAME} after timeout" >&2
  exit 1
fi
eval "${JOIN_COMMAND}"
```

### 1.5 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**:
  - `null_resource.apply_flannel_cni` re-runs (command string changed) — now waits for bootstrap completion before sending the Flannel command
  - Control plane bootstrap re-runs on next instance launch (user_data hash changed) — deletes the stale parameter at start, re-creates it at end
  - Worker bootstrap re-runs on next instance launch (user_data hash changed) — polls for the join command instead of single-shot
- **Rollback**: Revert all three files and re-apply (re-introduces the Flannel/bootstrap race)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Flannel provisioner waits for bootstrap-complete signal (`grep -q 'kubeadm-join-command' terraform/environments/dev/main.tf`)
- [ ] AC-003: Flannel provisioner deletes stale parameter before polling (`grep -q 'delete-parameter' terraform/environments/dev/main.tf`)
- [ ] AC-004: Worker bootstrap polls for join command (`grep -q 'seq 1 60' terraform/modules/worker-nodes/bootstrap.sh`)
- [ ] AC-005: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-006: Flannel CNI daemonset rolled out on the cluster (verified via SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 3. Assumptions & Constraints

- **Scope**: Provisioner + bootstrap corrections only; no change to SSM document, Flannel version, instance, or any Terraform resource
- **Bootstrap-complete signal**: the join-command parameter is published as the **last** step of the control plane bootstrap (after `kubeadm init` + kubeconfig copy), so its presence guarantees `kubectl` is installed and the API server is up
- **Per-run signal**: deleting the parameter at bootstrap start guarantees it only exists for the current run's completed bootstrap (no stale signal from a previous run)
- **Worker dependency**: the worker polls for the join command because it may boot before the control plane finishes; this is the correct dependency (workers need the control plane up to join)
- **CI runner SSM access**: the `get-parameter` in the Flannel provisioner runs on the GitHub Actions runner (PowerUserAccess role), which has `ssm:GetParameter` — no new IAM needed
- **Instance re-launch**: changing `user_data` (both bootstraps) changes the instance hash, so the control plane and workers are re-launched on the next apply — expected, no harm (fresh cluster)
- **Ordering**: This spec MUST be applied before 003-3's Flannel CNI is considered deployed; AC-006 (daemonset rollout) is the end-to-end proof the Flannel command ran to completion after bootstrap
