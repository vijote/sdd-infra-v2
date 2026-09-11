# Execution Graph (DAG): IMDS Token Expiry — Bootstrap Instance-ID Publication

**Input**: Design documents from `/specs/003-13-imds-token-expiry/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~5 min (agent file edit) + CI verification (control plane replacement)

---

## Stage 1: Implementation (Bootstrap Script)

- [x] T001 [Stage 1: Bootstrap] In `terraform/modules/control-plane/bootstrap.sh`: (1) move the `INSTANCE_ID` IMDS fetch from the end of the script (currently line 100, where the 300s token is expired) to the top, immediately after the `PRIVATE_IP` fetch (line 18-19), reusing the same fresh `IMDS_TOKEN`: `INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)`; (2) add a fail-fast guard after both fetches: `[ -n "${PRIVATE_IP}" ] && [ -n "${INSTANCE_ID}" ] || { echo "IMDS fetch failed (PRIVATE_IP='${PRIVATE_IP}' INSTANCE_ID='${INSTANCE_ID}')" >&2; exit 1; }`; (3) remove the now-redundant `INSTANCE_ID` fetch from the final publication step (line 100) — the step keeps the `aws ssm put-parameter --name /sdd-k8s-platform/kubeadm-bootstrap-instance-id --type String --value "${INSTANCE_ID}" --overwrite` call, using the value captured at the top. The instance ID is immutable for the instance's lifetime, so early capture is safe.

## Stage 2: Verification (CI-only)

- [ ] T002 [Stage 2: Static] AC-001: `terraform fmt -check -recursive && terraform validate` (Depends on T001)
- [ ] T003 [Stage 2: Plan] AC-002: `terraform plan -detailed-exitcode` exits 0 — expect a **control plane replacement** (user_data change is force-new) (Depends on T001)
- [ ] T004 [Stage 2: E2E] AC-003: Bootstrap instance-id parameter equals the current control plane instance ID (local: `IID=$(terraform output -raw control_plane_instance_id); PARAM=$(aws ssm get-parameter --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" --query 'Parameter.Value' --output text); [ "$PARAM" = "$IID" ]`) (Depends on T001)
- [ ] T005 [Stage 2: E2E] AC-004: Flannel daemonset fully rolled out — proves the 003-11 gate passed and the CNI applied (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s`) (Depends on T001)

---

## Parallelization Notes

- T001 is the only implementation task (single-file edit to `bootstrap.sh`).
- T002–T005 are CI gates that run after the apply. T002/T003 are static/plan checks (independent of each other); T004–T005 are E2E checks (independent of each other, both depend on the control plane replacement completing and the new user-data running).
- Per P5/P6, T004–T005 are **user-managed verification** — defined here but NOT added to `terraform-apply.yml`.
- Ordering note: T004 (parameter check) passes as soon as the new control plane's bootstrap finishes (~5 min after instance launch); T005 (Flannel rollout) additionally requires the 003-11 gate to pass and the Flannel apply to complete (several more minutes).
- The control plane replacement is expected and required (user-data only runs at first boot); workers re-join via the fresh join command published by the new control plane.
