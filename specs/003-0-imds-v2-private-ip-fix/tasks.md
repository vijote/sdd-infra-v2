# Execution Graph (DAG): IMDSv2 Private IP Fix

**Input**: Design documents from `/specs/003-0-imds-v2-private-ip-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification

---

## Stage 1: Bootstrap Script Correction

- [x] T001 [Stage 1: Bootstrap] In `terraform/modules/control-plane/bootstrap.sh`: (A) replace the bare IMDS `curl` (line 16) with the IMDSv2 token flow (`IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")` then `PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/local-ipv4)`); (B) correct the KubeletConfiguration `apiVersion` from `kubeadm.k8s.io/v1beta3` to `kubelet.k8s.io/v1beta1` (line 68)

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: IMDSv2 token is requested (`grep -q 'X-aws-ec2-metadata-token-ttl-seconds' terraform/modules/control-plane/bootstrap.sh`) (Depends on T002)
- [ ] T004 [Stage 2: Verify] AC-003: The metadata call passes the token (`grep -q 'X-aws-ec2-metadata-token: ${IMDS_TOKEN}' terraform/modules/control-plane/bootstrap.sh`) (Depends on T003)
- [ ] T005 [Stage 2: Verify] AC-004: KubeletConfiguration uses the correct GVK (`grep -q 'apiVersion: kubelet.k8s.io/v1beta1' terraform/modules/control-plane/bootstrap.sh`) (Depends on T004)
- [ ] T006 [Stage 2: Verify] AC-005: Join command published to SSM after instance re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → end-to-end SSM proof)
- **Ordering constraint**: T001's apply replaces the control plane instance (user_data hash change); T006 only passes once the new instance's bootstrap completes

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle) — both fixes (IMDSv2 flow + GVK correction) are in the same bootstrap script
- **No Terraform resource changes**: bootstrap-script-only correction — the `user_data` hash change forces instance replacement, which is the intended re-run mechanism
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
