# Spec: Flannel Join-Param Delete Removal

**Feature Branch**: `003-8-flannel-join-param-delete-removal` | **Date**: 2026-09-06 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform provisioner command correction only — no new AWS resources, no resource changes
- **Kubernetes Scope**: None (Flannel CNI apply is unchanged; only the readiness gate is corrected)
- **AWS Scope**: SSM Parameter Store read-only (the provisioner no longer deletes the join-command parameter)
- **Terraform Scope**: `terraform/environments/dev/main.tf` — `null_resource "apply_flannel_cni"` `local-exec` provisioner

## 2. Problem Statement

The 003-7 fix added a "bootstrap complete" gate to the Flannel provisioner: it deletes the
`/sdd-k8s-platform/kubeadm-join-command` SSM parameter, then waits for it to (re-)appear as a
per-run signal that the control plane finished `kubeadm init`.

This is wrong because the control plane is a **persistent** resource. `bootstrap.sh` is EC2
user-data — it runs **once at first boot**, not on every `terraform apply`. On a subsequent
apply the control plane already exists, so:

1. The join-command parameter **already exists** (published by the original bootstrap).
2. The provisioner **deletes** it.
3. The control plane does **not** re-run `bootstrap.sh`, so the parameter is **never re-published**.
4. The wait polls 600s, finds nothing, and fails:
   `Control plane bootstrap did not complete within timeout`.

The delete is the only defect. The SSM-agent wait and the bootstrap-complete wait are correct.

## 3. Solution

Remove the `aws ssm delete-parameter` step. The provisioner then simply **waits for the
join-command parameter to exist**:

| Scenario | Param state | Wait behavior |
|----------|-------------|---------------|
| First apply (control plane bootstrapping) | absent until `kubeadm init` finishes | blocks until bootstrap publishes it |
| Subsequent apply (persistent control plane) | already present | returns immediately |
| Flannel version change (provisioner re-runs) | already present | returns immediately |

The parameter is a valid "bootstrap complete" signal in all three cases: its presence means
`kubeadm init` has finished and `kubectl` + the API server are ready for `kubectl apply`.

### Collateral: workers from the 003-7 run

The 003-7 run recreated the worker nodes (their `bootstrap.sh` changed). Their bootstrap polls
for the **same** join-command parameter — which the provisioner deleted and never re-published.
Those workers timed out and **never joined the cluster**. Removing the delete fixes the
provisioner, but those already-broken workers must be **recreated** to join. This is a one-time
operational step (see AC-005), not a code change.

## 4. Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: The `delete-parameter` step is removed (`! grep -qF 'delete-parameter' terraform/environments/dev/main.tf`)
- [ ] AC-003: The bootstrap-complete wait is retained (`grep -qF 'Control plane bootstrap complete' terraform/environments/dev/main.tf`)
- [ ] AC-004: `terraform plan -detailed-exitcode` exits 0 (no resource changes; only the provisioner command changes)
- [ ] AC-005: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Out of Scope

- No changes to the control-plane or worker-nodes modules
- No changes to the SSM-agent readiness wait (003-4) or the JSON escaping (003-6)
- No changes to the Flannel manifest URL or version pin
- No changes to the worker join-command poll (003-7)
