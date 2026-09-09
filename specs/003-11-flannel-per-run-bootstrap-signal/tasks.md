# Execution Graph (DAG): Flannel Per-Run Bootstrap Signal

**Input**: Design documents from `/specs/003-11-flannel-per-run-bootstrap-signal/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edits) + CI verification

---

## Stage 1: Per-Run Signal (control plane)

- [x] T001 [Stage 1: Control Plane] In `terraform/modules/control-plane/bootstrap.sh`: after the existing join-command `put-parameter` block (lines 88-94), add a block that reads the control plane's instance ID from IMDSv2 (reusing `${IMDS_TOKEN}`) and publishes it to `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` (`--type String --overwrite`) as the last step.

## Stage 2: Flannel Gate (dev env)

- [x] T002 [Stage 2: Flannel Gate] In `terraform/environments/dev/main.tf`: in the `local-exec` provisioner of `null_resource "apply_flannel_cni"`, replace the bootstrap-complete wait (the `for i in $(seq 1 60)` loop that polls the join-command param until non-empty, plus its trailing `if [ -z ... ]` check) with a loop that polls `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` until it equals `$${INSTANCE_ID}`, and a trailing `if [ "$${BOOTSTRAP_ID}" != "$${INSTANCE_ID}" ]` timeout check. The SSM-agent wait, the `send-command`, the KUBECONFIG-prefixed `kubectl apply` (003-9), and the status-poll query (003-10) are byte-for-byte unchanged. (Depends on T001)

## Stage 3: Worker Bootstrap

- [x] T003 [Stage 3: Worker] In `terraform/modules/worker-nodes/main.tf`: change `user_data = file("${path.module}/bootstrap.sh")` (line 37) to `user_data = replace(file("${path.module}/bootstrap.sh"), "%%CONTROL_PLANE_INSTANCE_ID%%", var.control_plane_instance_id)`.
- [x] T004 [Stage 3: Worker] In `terraform/modules/worker-nodes/bootstrap.sh`: add `CONTROL_PLANE_INSTANCE_ID="%%CONTROL_PLANE_INSTANCE_ID%%"` and `BOOTSTRAP_ID_PARAM="/sdd-k8s-platform/kubeadm-bootstrap-instance-id"` near the top; before the existing join-command fetch, add a 60×10s loop that polls `BOOTSTRAP_ID_PARAM` until it equals `CONTROL_PLANE_INSTANCE_ID` (with a timeout `exit 1`); keep the existing join-command fetch + `eval` after the gate. (Depends on T003)

## Stage 4: Verification (CI-only)

- [ ] T005 [Stage 4: Static] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] T006 [Stage 4: Static] AC-002: `grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/control-plane/bootstrap.sh`
- [ ] T007 [Stage 4: Static] AC-003: `grep -qF 'BOOTSTRAP_ID}" = "$${INSTANCE_ID}' terraform/environments/dev/main.tf`
- [ ] T008 [Stage 4: Static] AC-004: `grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/worker-nodes/bootstrap.sh`
- [ ] T009 [Stage 4: Static] AC-005: `grep -qF 'replace(file("${path.module}/bootstrap.sh")' terraform/modules/worker-nodes/main.tf`
- [ ] T010 [Stage 4: Plan] AC-006: `terraform plan -detailed-exitcode` exits 0
- [ ] T011 [Stage 4: E2E] AC-007: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)
- [ ] T012 [Stage 4: E2E] AC-008: All 3 nodes Ready (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers | grep -c ' Ready'` returns `3`)

---

## Parallelization Notes

- T001 (control plane) is independent; T002 (Flannel gate) and T003/T004 (worker) depend on the signal existing conceptually but are separate file edits — T002 depends on T001, T004 depends on T003.
- T005-T012 are CI gates that run after the apply.
- T005-T009 are independent static checks and can run in parallel in CI.
- T010 (plan) and T011/T012 (E2E) depend on the apply completing.
