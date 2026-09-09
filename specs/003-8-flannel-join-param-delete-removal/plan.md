# Architecture Delta: Flannel Join-Param Delete Removal

**Branch**: `003-8-flannel-join-param-delete-removal` | **Date**: 2026-09-06 | **Spec**: specs/003-8-flannel-join-param-delete-removal/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | Remove the `aws ssm delete-parameter` step (lines 87-91) from the `local-exec` provisioner in `null_resource "apply_flannel_cni"`; keep the SSM-agent wait and the bootstrap-complete wait unchanged |

## 2. Architecture Delta

The Flannel provisioner's readiness gate changes from "delete the join-command parameter, then
wait for it to re-appear" to "wait for the join-command parameter to exist".

- **Before**: `delete-parameter` → wait SSM agent → wait param re-appears (600s) → send Flannel.
  Fails on persistent control planes because the param is never re-published.
- **After**: wait SSM agent → wait param exists (600s) → send Flannel. Succeeds on both first
  apply (param appears when bootstrap finishes) and subsequent applies (param already present).

No resource graph changes. The `null_resource` triggers, `depends_on`, and the SSM
`send-command` + poll loop are byte-for-byte unchanged.

## 3. Rollout Stages

1. **Provisioner edit (agent)** — remove the `delete-parameter` block (lines 87-91) from
   `terraform/environments/dev/main.tf`.
2. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate`;
   grep gates (AC-002/AC-003); `terraform plan -detailed-exitcode` (AC-004).
3. **End-to-end verification (CI)** — apply runs; the provisioner finds the existing join-command
   parameter immediately and sends the Flannel command; the Flannel daemonset rolls out (AC-005).
   One-time: recreate the 003-7 workers so they join (their bootstrap had timed out on the
   deleted parameter).

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `! grep -qF 'delete-parameter' terraform/environments/dev/main.tf`
- **AC-003**: `grep -qF 'Control plane bootstrap complete' terraform/environments/dev/main.tf`
- **AC-004**: `terraform plan -detailed-exitcode`
- **AC-005**: Flannel daemonset rolled out (SSM Run Command on control plane: `kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A stale join-command parameter from a different cluster is read | Parameter name is cluster-scoped (`/sdd-k8s-platform/`); the control plane is the sole publisher |
| The 003-7 workers are already broken (timed out on the deleted param) | One-time recreation step (AC-005); their bootstrap polls for the param, which now persists |
| Removing the delete changes behavior on a *fresh* cluster | None — on a fresh cluster the param is absent until bootstrap publishes it, so the wait still blocks correctly |
