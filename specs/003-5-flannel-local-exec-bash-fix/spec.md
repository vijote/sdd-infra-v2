# Spec: Flannel Local-Exec Bash Fix

**Feature Branch**: `003-5-flannel-local-exec-bash-fix` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner interpreter correction only — no new AWS resources, no resource changes
- **Kubernetes / Cluster Scope**: Worker nodes module (003-3-worker-nodes) — Flannel CNI application step
- **Target Service**: `terraform/environments/dev/main.tf` (`null_resource "apply_flannel_cni"` local-exec provisioner)
- **Root Cause (fatal)**: `terraform apply` fails with `Error running command ... exit status 2. Output: /bin/sh: 1: set: Illegal option -o pipefail`. The `local-exec` provisioner runs its command via `/bin/sh -c` by default. On GitHub's `ubuntu-latest` runner, `/bin/sh` is **dash**, which does not support `set -o pipefail` (a bashism). The first line of the provisioner script aborts before any `aws ssm` command executes, so the Flannel CNI is never applied.
- **Decision**: Add `interpreter = ["/bin/bash", "-c"]` to the `local-exec` provisioner. This is the documented Terraform mechanism to control the shell used for `local-exec` commands. It preserves `set -euo pipefail` and all existing script logic unchanged.

### 1.1 Terraform Provisioner Contract

File: `terraform/environments/dev/main.tf`

**Before (broken — default `/bin/sh` = dash, no `pipefail`):**

```hcl
resource "null_resource" "apply_flannel_cni" {
  depends_on = [module.worker_nodes]
  triggers   = { flannel_version = local.flannel_version }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      # ... (SSM send-command + poll loop)
    EOT
  }
}
```

**After (fixed — explicit bash interpreter):**

```hcl
resource "null_resource" "apply_flannel_cni" {
  depends_on = [module.worker_nodes]
  triggers   = { flannel_version = local.flannel_version }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      # ... (SSM send-command + poll loop, unchanged)
    EOT
  }
}
```

- **Why `interpreter`**: Terraform's `local-exec` provisioner accepts an `interpreter` argument (list of strings) that specifies the shell and flags to run the command. Default is `["/bin/sh", "-c"]`. Setting it to `["/bin/bash", "-c"]` ensures bash semantics (including `pipefail`) on all runners.
- **No script changes**: the `command` heredoc (SSM send-command, poll loop, status checks) is byte-for-byte unchanged. Only the `interpreter` line is added.
- **No other changes**: `module.worker_nodes`, `module.control_plane`, `module.cluster_plumbing`, `module.vpc`, and all other resources are untouched.

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `null_resource.apply_flannel_cni` is a null resource; changing its `interpreter` changes the provisioner configuration, forcing Terraform to re-run the provisioner on the next apply. The SSM command is re-issued to the control plane instance, and the Flannel CNI manifest is applied
- **Rollback**: Remove the `interpreter` line and re-apply (reverts to `/bin/sh`, which will fail again on `pipefail` — rollback is only meaningful if the script is also changed to drop `pipefail`)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: `interpreter` argument present on the local-exec provisioner (`grep -q 'interpreter = \["/bin/bash", "-c"\]' terraform/environments/dev/main.tf`)
- [ ] AC-003: `set -euo pipefail` still present in the provisioner command (`grep -q 'set -euo pipefail' terraform/environments/dev/main.tf`)
- [ ] AC-004: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-005: Flannel CNI daemonset rolled out on the cluster (verified via SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 3. Assumptions & Constraints

- **Scope**: Provisioner-interpreter-only correction; no change to SSM command, Flannel version, instance, or any Terraform resource
- **Bash availability**: `/bin/bash` is present on GitHub's `ubuntu-latest` runner (Ubuntu 22.04+ ships bash by default); no additional package install required
- **Null resource re-run**: changing the `interpreter` argument changes the provisioner's computed configuration, so Terraform re-runs the provisioner on the next apply — the SSM command is re-issued and the Flannel manifest is re-applied (idempotent `kubectl apply`)
- **Ordering**: This spec MUST be applied before 003-3's Flannel CNI is considered deployed; AC-005 (daemonset rollout) is the end-to-end proof the provisioner ran to completion
