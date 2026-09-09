# Spec: Flannel SSM Kubeconfig Fix

**Feature Branch**: `003-9-flannel-ssm-kubeconfig-fix` | **Date**: 2026-09-09 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner command correction only — no new AWS resources, no resource changes
- **Kubernetes Scope**: None (Flannel CNI apply is unchanged; only the `kubectl` invocation environment is corrected)
- **AWS Scope**: SSM Run Command (the `kubectl apply` command string gains a `KUBECONFIG` prefix)
- **Terraform Scope**: `terraform/environments/dev/main.tf` — `null_resource "apply_flannel_cni"` `local-exec` provisioner, `send-command` `--parameters`

## 2. Problem Statement

The Flannel provisioner sends an SSM Run Command that runs two shell commands on the control
plane:

```
curl -sSL <flannel-url> -o /tmp/kube-flannel.yml
kubectl apply -f /tmp/kube-flannel.yml
```

The `kubectl apply` fails with:

```
couldn't get current server API group list: Get "http://localhost:8080/api": dial tcp 127.0.0.1:8080: connect: connection refused
The connection to the server localhost:8080 was refused - did you specify the right host or port?
failed to run commands: exit status 1
```

`localhost:8080` is kubectl's **default fallback** when it cannot locate a kubeconfig. SSM Run
Command executes in a **minimal environment** where `HOME` and `KUBECONFIG` are not set, so
kubectl never finds `/root/.kube/config` (created by `bootstrap.sh` lines 85-86) and falls back
to `localhost:8080` → refused.

**Root cause confirmed by direct SSM probe** (control plane `i-07751e000aef289a2`):

| Command | Result | Verdict |
|---------|--------|---------|
| `curl -sSL --max-time 30 <flannel-url>` | `HTTP 200`, `CURL_EXIT=0`, 4398 bytes, valid YAML | egress + URL are fine |
| `kubectl apply -f /tmp/kube-flannel.yml` | `Get "http://localhost:8080/api"` → connection refused | no kubeconfig in SSM env |

The `curl` step succeeds (egress via NAT works, the manifest URL is valid). Only the `kubectl`
step fails, and only because of the missing kubeconfig. This is unrelated to the 003-7
bootstrap-complete gate (which already passed) and to 003-8 (the `delete-parameter` step).

## 3. Solution

Prefix the `kubectl apply` command with an explicit `KUBECONFIG` pointing at the canonical
kubeadm admin kubeconfig:

```
KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml
```

- **Why `/etc/kubernetes/admin.conf`**: it is written by `kubeadm init` and is always present
  after bootstrap completes (the 003-7 gate guarantees this). It does not depend on the
  `/root/.kube/config` copy, and it is readable by root — the default user SSM Run Command runs
  as on Linux.
- **No `sudo` needed**: SSM Run Command runs as root by default; the existing command already
  omits `sudo`.
- **No heredoc escaping needed**: the new command string contains no `$` characters, so it is
  safe inside the `<<-EOT` heredoc as-is.
- **No IAM change**: the command still runs on the control plane via the existing node instance
  profile; only the command string changes.

### Re-run note

A `null_resource` re-runs its provisioners only on creation, on a `triggers` change, or on
replacement. Changing the `command` string alone does **not** re-trigger it. The dev workflow
recreates the control plane each run (destroy + apply), so the `null_resource` is created fresh
and the corrected provisioner runs. To force a re-run without a full destroy, `terraform taint`
the `null_resource` or bump `local.flannel_version`.

## 4. Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: The `KUBECONFIG`-prefixed command is present (`grep -qF 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml' terraform/environments/dev/main.tf`)
- [ ] AC-003: The bare `kubectl apply` (without `KUBECONFIG`) is gone (`! grep -qF '\"kubectl apply' terraform/environments/dev/main.tf`)
- [ ] AC-004: `terraform plan -detailed-exitcode` exits 0 (no resource changes; only the provisioner command changes)
- [ ] AC-005: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Out of Scope

- No changes to the control-plane or worker-nodes modules
- No changes to the SSM-agent readiness wait (003-4), the JSON escaping (003-6), or the bootstrap-complete gate (003-7)
- No changes to the Flannel manifest URL or version pin
- No changes to the `delete-parameter` step (003-8 — deferred)
