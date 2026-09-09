# Technical Quality Checklist: Flannel SSM Kubeconfig Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-09
**Feature**: [Flannel SSM Kubeconfig Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] Terraform provisioner command is fully specified (add `KUBECONFIG` prefix to `kubectl apply`)
- [x] SSM Run Command interaction is unchanged (same document, same instance, same poll loop)
- [x] No new AWS resources or resource changes
- [x] Root cause is confirmed by a direct SSM probe (curl HTTP 200, kubectl `localhost:8080` refused)

## 2. Infrastructure Contract Rigor
- [x] Target file and resource are explicit (`terraform/environments/dev/main.tf`, `null_resource "apply_flannel_cni"`)
- [x] The corrected command is byte-level specified (`KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml`)
- [x] The kubeconfig path choice is justified (canonical kubeadm location, present after bootstrap, root-readable)
- [x] The re-run trigger behavior of `null_resource` is documented

## 3. Machine-Verifiability
- [x] All acceptance criteria are executable in CI/CD (GitHub Actions)
- [x] AC-002/AC-003 use `grep -qF` (fixed strings) — no regex escaping
- [x] AC-004 uses `terraform plan -detailed-exitcode`
- [x] AC-005 uses `kubectl rollout status` via SSM Run Command

## 4. Security & Compliance
- [x] No secrets or credentials in the change
- [x] No IAM policy changes
- [x] No network exposure changes

## 5. Risk Assessment
- [x] Risk: `/etc/kubernetes/admin.conf` absent if bootstrap incomplete — mitigated by the 003-7 bootstrap-complete gate (the provisioner only sends the command after the join-command parameter is published)
- [x] Risk: `null_resource` not re-triggered by a command-only change — mitigated by the dev workflow recreating the control plane each run (documented in spec §3)
