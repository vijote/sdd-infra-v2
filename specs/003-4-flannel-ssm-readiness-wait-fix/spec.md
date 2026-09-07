# Spec: Flannel SSM Readiness Wait Fix

**Feature Branch**: `003-4-flannel-ssm-readiness-wait-fix` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner command correction only — no new AWS resources, no resource changes
- **Kubernetes / Cluster Scope**: Worker nodes module (003-3-worker-nodes) — Flannel CNI application step
- **Target Service**: `terraform/environments/dev/main.tf` (`null_resource "apply_flannel_cni"` local-exec provisioner)
- **Root Cause (fatal)**: `terraform apply` fails with `aws: [ERROR]: An error occurred (InvalidInstanceId) when calling the SendCommand operation: Instances not in a valid state`. The provisioner calls `aws ssm send-command` exactly once, immediately after the worker nodes are created (~60s after the control plane launches). The control plane is freshly launched each run (the instance ID differs across runs). The SSM agent on a fresh AL2023 instance registers **after** the EC2 `running` state that Terraform waits for — it lags by ~30-90s. So `send-command` fires before the agent is registered, and SSM rejects the instance as "not in a valid state". There is no readiness wait before `send-command`.
- **Decision**: Add a readiness-wait loop **before** `send-command` that polls `aws ssm describe-instance-information --filters "Key=InstanceIds,Values=<id>"` until the instance appears as a registered SSM target (agent connected). Only then send the command. If the agent does not register within the timeout, fail with a clear error.

### 1.1 Terraform Provisioner Command Contract

File: `terraform/environments/dev/main.tf`

**Before (broken — `send-command` fires before the SSM agent registers):**

```hcl
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      FLANNEL_URL="${local.flannel_manifest_url}"
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        # ... (no readiness wait)
    EOT
  }
```

**After (fixed — wait for SSM agent registration, then send):**

```hcl
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      FLANNEL_URL="${local.flannel_manifest_url}"
      # Wait for the control plane's SSM agent to register (fresh instance: agent
      # starts after boot and lags behind the EC2 'running' state Terraform waits for).
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        if [ "$${SSM_ID}" = "$${INSTANCE_ID}" ]; then
          echo "SSM agent registered for $${INSTANCE_ID}"
          break
        fi
        sleep 10
      done
      if [ "$${SSM_ID}" != "$${INSTANCE_ID}" ]; then
        echo "SSM agent did not register for $${INSTANCE_ID} within timeout" >&2
        exit 1
      fi
      CMD_ID=$(aws ssm send-command \
        --instance-ids "$${INSTANCE_ID}" \
        # ... (unchanged)
    EOT
  }
```

- **Readiness check**: `aws ssm describe-instance-information` returns the instance in `InstanceInformationList` only once the SSM agent has registered. Before registration, the filtered list is empty and the JMESPath query yields `None` (or `Pending` on a transient CLI error). The loop exits as soon as `SSM_ID` equals `INSTANCE_ID`.
- **Timeout**: 30 iterations × 10s = 300s (5 min). The SSM agent typically registers within 1-2 min of boot; 5 min is generous. If it does not register, the provisioner fails with a clear error instead of a confusing `InvalidInstanceId`.
- **No other changes**: the `interpreter` line, the `--parameters` JSON (already fixed), the SSM send-command flags, and the existing invocation poll loop are byte-for-byte unchanged. Only the readiness-wait block is inserted before `send-command`.

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `null_resource.apply_flannel_cni` is a null resource; changing the `command` string changes the provisioner configuration, forcing Terraform to re-run the provisioner on the next apply. The provisioner now waits for SSM registration before sending the command, so the Flannel CNI manifest is applied once the agent is ready
- **Rollback**: Remove the readiness-wait block and re-apply (re-introduces the `InvalidInstanceId` race)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: SSM readiness wait present (`grep -q 'describe-instance-information' terraform/environments/dev/main.tf`)
- [ ] AC-003: SSM registration timeout guard present (`grep -q 'SSM agent did not register' terraform/environments/dev/main.tf`)
- [ ] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-005: Flannel CNI daemonset rolled out on the cluster (verified via SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 3. Assumptions & Constraints

- **Scope**: Provisioner-command-only correction; no change to SSM document, Flannel version, instance, or any Terraform resource
- **SSM agent registration lag**: the SSM agent is a systemd service that starts at boot and registers with SSM asynchronously; this registration lags behind the EC2 `running` state that the `aws_instance` resource waits for. The wait loop bridges this gap
- **Network is not the issue**: the control plane already reaches SSM (it published the join command via `aws ssm put-parameter` in 003-2), so outbound SSM connectivity via NAT is confirmed; the failure is purely a registration-timing race
- **`describe-instance-information` semantics**: a non-matching filter returns an empty `InstanceInformationList` (exit 0); the JMESPath query yields `None`, which the loop treats as "not yet registered"
- **Null resource re-run**: changing the `command` string forces the provisioner to re-run; the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)
- **Ordering**: This spec MUST be applied before 003-3's Flannel CNI is considered deployed; AC-005 (daemonset rollout) is the end-to-end proof the SSM command was accepted and ran to completion
