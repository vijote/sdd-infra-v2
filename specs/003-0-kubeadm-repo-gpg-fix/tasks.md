# Execution Graph (DAG): Kubeadm Repo GPG Fix

**Input**: Design documents from `/specs/003-0-kubeadm-repo-gpg-fix/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification

---

## Stage 1: Bootstrap Script Correction

- [x] T001 [Stage 1: Bootstrap] Replace `dnf config-manager --add-repo https://pkgs.k8s.io/core:/stable:/v1.28/rpm/` (line 27) with an explicit `/etc/yum.repos.d/kubernetes.repo` heredoc (`baseurl`, `enabled=1`, `gpgcheck=1`, `gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key`) in `terraform/modules/control-plane/bootstrap.sh`

---

## Stage 2: Verification (CI-only — executed in GitHub Actions, never locally)

- [x] T002 [Stage 2: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T001)
- [x] T003 [Stage 2: Verify] AC-002: Repo file declares the GPG key (`grep -q 'gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key' terraform/modules/control-plane/bootstrap.sh`) (Depends on T002)
- [x] T004 [Stage 2: Verify] AC-003: Repo file enables GPG checking (`grep -q 'gpgcheck=1' terraform/modules/control-plane/bootstrap.sh`) (Depends on T003)
- [x] T005 [Stage 2: Verify] AC-004: The bare `--add-repo` line is removed (`! grep -q 'config-manager --add-repo' terraform/modules/control-plane/bootstrap.sh`) (Depends on T004)
- [x] T006 [Stage 2: Verify] AC-005: Join command published to SSM after instance re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`) (Depends on T005)

---

## Dependencies / Execution Order

```
T001 ─ T002 ─ T003 ─ T004 ─ T005 ─ T006
```

- **Sequential**: T001 → T002 → T003 → T004 → T005 → T006 (edit → static checks → end-to-end SSM proof)
- **Ordering constraint**: T001's apply replaces the control plane instance (user_data hash change); T006 only passes once the new instance's bootstrap completes

## Notes

- **1:1 file mapping**: T001 touches exactly one file (constitution DAG principle)
- **No Terraform resource changes**: bootstrap-script-only correction — the `user_data` hash change forces instance replacement, which is the intended re-run mechanism
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 2 tasks run in GitHub Actions CI only — never locally
