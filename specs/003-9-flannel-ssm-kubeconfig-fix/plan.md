# Architecture Delta: Flannel SSM Kubeconfig Fix

**Branch**: `003-9-flannel-ssm-kubeconfig-fix` | **Date**: 2026-09-09 | **Spec**: specs/003-9-flannel-ssm-kubeconfig-fix/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | In the `local-exec` provisioner of `null_resource "apply_flannel_cni"`, prefix the `kubectl apply` command in the `send-command` `--parameters` with `KUBECONFIG=/etc/kubernetes/admin.conf` (line 130). No other change. |

## 2. Architecture Delta

The Flannel provisioner's `kubectl apply` command changes from a bare invocation to one with an
explicit kubeconfig:

- **Before**: `kubectl apply -f /tmp/kube-flannel.yml` — fails in the SSM Run Command environment
  because `HOME`/`KUBECONFIG` are unset, so kubectl falls back to `localhost:8080` (refused).
- **After**: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml` —
  points kubectl at the canonical kubeadm admin kubeconfig, which is present after bootstrap
  (guaranteed by the 003-7 gate) and readable by root (the SSM default user).

No resource graph changes. The `null_resource` triggers, `depends_on`, the SSM-agent wait, the
bootstrap-complete wait, the `curl` step, and the `send-command` + poll loop are byte-for-byte
unchanged. Only the second element of the `--parameters` `commands` array changes.

## 3. Rollout Stages

1. **Provisioner edit (agent)** — change the `kubectl apply` command string in
   `terraform/environments/dev/main.tf` (line 130) to add the `KUBECONFIG` prefix.
2. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate`;
   grep gates (AC-002/AC-003); `terraform plan -detailed-exitcode` (AC-004).
3. **End-to-end verification (CI)** — apply runs; the provisioner sends the Flannel command with
   the corrected `kubectl` invocation; the Flannel daemonset rolls out (AC-005).

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `grep -qF 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml' terraform/environments/dev/main.tf`
- **AC-003**: `! grep -qF '\"kubectl apply' terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `/etc/kubernetes/admin.conf` absent if bootstrap incomplete | The 003-7 bootstrap-complete gate only sends the command after the join-command parameter is published (i.e. after `kubeadm init` + kubeconfig copy) |
| `null_resource` not re-triggered by a command-only change | The dev workflow recreates the control plane each run (destroy + apply), so the `null_resource` is created fresh; alternatively `terraform taint` the resource or bump `local.flannel_version` |
| SSM user cannot read the kubeconfig | SSM Run Command runs as root by default; `/etc/kubernetes/admin.conf` is root-readable |
