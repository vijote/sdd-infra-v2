# Execution Graph (DAG): Kubeadm Preflight Sysctl Fix

**Input**: Design documents from `/specs/003-0-kubeadm-preflight-sysctl-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification

---

## Stage 1: Bootstrap Script Correction

- [x] T001 [Stage 1: Bootstrap] In `terraform/modules/control-plane/bootstrap.sh`: (A) insert `modprobe br_netfilter` + `/etc/sysctl.d/99-kubernetes.conf` heredoc (`net.bridge.bridge-nf-call-iptables = 1`, `net.bridge.bridge-nf-call-ip6tables = 1`, `net.ipv4.ip_forward = 1`) + `sysctl --system` after the AWS CLI install block and before the kubeadm config write; (B) remove the KubeletConfiguration document (the `---` separator + `apiVersion: kubelet.k8s.io/v1beta1` + `kind: KubeletConfiguration` + `cgroupDriver: systemd` lines) from the kubeadm config heredoc so it ends after the ClusterConfiguration document

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: br_netfilter module is loaded (`grep -q 'modprobe br_netfilter' terraform/modules/control-plane/bootstrap.sh`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: Sysctl file enables bridge netfilter (`grep -q 'net.bridge.bridge-nf-call-iptables = 1' terraform/modules/control-plane/bootstrap.sh`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: Sysctl file enables IP forwarding (`grep -q 'net.ipv4.ip_forward = 1' terraform/modules/control-plane/bootstrap.sh`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: KubeletConfiguration document removed (`! grep -q 'kind: KubeletConfiguration' terraform/modules/control-plane/bootstrap.sh`) (Depends on T005)
- [ ] T007 [Stage 2: Verify] AC-006: Join command published to SSM after instance re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`) (Depends on T006)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006 ─ T007
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 → T007 (edit → static checks → end-to-end SSM proof)
- **Ordering constraint**: T001's apply replaces the control plane instance (user_data hash change); T007 only passes once the new instance's bootstrap completes

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — both fixes (br_netfilter + sysctls, KubeletConfiguration removal) are in the same bootstrap script
- **No Terraform resource changes**: bootstrap-script-only correction — the `user_data` hash change forces instance replacement, which is the intended re-run mechanism
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
