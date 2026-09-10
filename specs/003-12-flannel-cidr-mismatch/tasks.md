# Execution Graph (DAG): Flannel CNI CIDR Mismatch Fix

**Input**: Design documents from `/specs/003-12-flannel-cidr-mismatch/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification

---

## Stage 1: Implementation (Terraform)

- [x] T001 [Stage 1: Flannel] In `terraform/environments/dev/main.tf`, modify `null_resource "apply_flannel_cni"`: (1) in the SSM `--parameters` command list, insert a sed step between the `curl` and the `kubectl apply`: `sed -i 's/10\.244\.0\.0\/16/192.168.0.0\/16/g' /tmp/kube-flannel.yml` (rewrite the stock manifest's `net-conf.json` Network CIDR to match the kubeadm podSubnet `192.168.0.0/16`); (2) append a daemonset restart after the apply: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout restart ds/kube-flannel-ds` (so flanneld re-reads the config on a persistent cluster); (3) add `pod_cidr = "192.168.0.0/16"` to the `triggers` block so the provisioner re-runs when the pod CIDR changes. Keep the existing SSM-agent wait, bootstrap-instance-id gate (003-11), and poll loop (003-10) unchanged.

## Stage 2: Verification (CI-only)

- [ ] T002 [Stage 2: Static] AC-001: `terraform fmt -check -recursive && terraform validate` (Depends on T001)
- [ ] T003 [Stage 2: Plan] AC-002: `terraform plan -detailed-exitcode` exits 0 (Depends on T001)
- [ ] T004 [Stage 2: E2E] AC-003: Flannel `net-conf.json` Network CIDR is `192.168.0.0/16` (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel get cm kube-flannel-cfg -o jsonpath={.data}` contains `192.168.0.0/16`) (Depends on T001)
- [ ] T005 [Stage 2: E2E] AC-004: Flannel daemonset fully rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s`) (Depends on T001)
- [ ] T006 [Stage 2: E2E] AC-005: CoreDNS pods Ready — proves pods get pod IPs, closing the gap 003-11 missed (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=300s`) (Depends on T001)

---

## Parallelization Notes

- T001 is the only implementation task (single-file edit to the existing `apply_flannel_cni` resource).
- T002–T006 are CI gates that run after the apply. T002/T003 are static/plan checks (independent of each other); T004–T006 are E2E SSM checks (independent of each other, all depend on the apply completing).
- Per P5/P6, T004–T006 are **user-managed verification** (SSM Run Command against the live cluster) — defined here but NOT added to `terraform-apply.yml`.
- Ordering note: T004 (ConfigMap CIDR) should pass immediately after the apply; T005 (daemonset rollout) and T006 (CoreDNS Ready) may need a few minutes for the flannel pods to restart and pods to get IPs.
