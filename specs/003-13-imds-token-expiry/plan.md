# Architecture Delta: IMDS Token Expiry — Bootstrap Instance-ID Publication

**Branch**: `003-13-imds-token-expiry` | **Date**: 2026-09-11 | **Spec**: specs/003-13-imds-token-expiry/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/bootstrap.sh` | Modify | (1) Move the `INSTANCE_ID` IMDS fetch from the end of the script (line 100, token expired) to the top (line ~19, alongside `PRIVATE_IP`, token fresh); (2) add a fail-fast guard after both fetches: `[ -n "${PRIVATE_IP}" ] && [ -n "${INSTANCE_ID}" ] \|\| { echo "IMDS fetch failed" >&2; exit 1; }`; (3) the final publication step (line 102-106) now uses the `INSTANCE_ID` captured at the top instead of re-fetching |

No Terraform resource changes. The control-plane module embeds the script via `user_data = file("${path.module}/bootstrap.sh")` (main.tf:28). Because `user_data` is a **force-new** attribute on `aws_instance`, editing the script changes the `user_data` hash → the next apply **replaces** the control plane instance → the new user-data runs at first boot. This is the required mechanism (user-data only executes at first boot).

## 2. Architecture Delta

The control-plane bootstrap goes from "instance-id publication fails (expired IMDS token) → 003-11 gate times out" to "instance-id publishes correctly → gate passes → Flannel + workers proceed".

- **Before**: `bootstrap.sh` obtains an IMDSv2 token (300s TTL) at line 16, fetches `PRIVATE_IP` at line 18 (works — token fresh), then runs ~5 min of work (dnf, `kubeadm init`), then fetches `INSTANCE_ID` at line 100 (token **expired** → 401 → `curl -s` swallows it → empty). `put-parameter` rejects the empty value (`ValidationException`) → the 003-11 gate (Flannel `apply_flannel_cni` + worker bootstrap) times out after 10 min.
- **After**: `INSTANCE_ID` is fetched at the top (line ~19) alongside `PRIVATE_IP`, while the token is seconds old. A guard fails fast with a clear log line if either value is empty. The final publication step uses the captured value. The instance ID is immutable for the instance's lifetime, so early capture is safe.

**Why move the fetch (not re-obtain a fresh token at the end)**: both work, but moving the fetch is simpler (one fewer IMDS call, no second token acquisition) and the instance ID is immutable, so there's no correctness difference. The guard is added regardless, so a future IMDS regression fails fast with a clear message instead of a cryptic `put-parameter` error.

**Why this unblocks 003-12**: the 003-11 gate (which 003-12's Flannel apply depends on) waits for `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` to equal the current instance ID. Until the publication succeeds, the gate times out and Flannel never applies. Fixing the publication is a prerequisite for 003-12 to work on a fresh apply.

## 3. Rollout Stages

1. **Edit bootstrap.sh (agent)** — move the `INSTANCE_ID` fetch to the top, add the guard, update the publication step to use the captured value.
2. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate` (AC-001); `terraform plan -detailed-exitcode` (AC-002). The plan will show a **control plane replacement** (user_data change) — expected.
3. **End-to-end verification (CI, user-managed)** — the apply replaces the control plane; the new user-data runs; the instance-id publishes; AC-003 (param equals instance ID) and AC-004 (Flannel daemonset rolled out) verified via SSM.

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `terraform plan -detailed-exitcode` (expect a control plane replacement)
- **AC-003**: Bootstrap instance-id parameter equals the current control plane instance ID (`aws ssm get-parameter ... --query 'Parameter.Value'` == `terraform output -raw control_plane_instance_id`)
- **AC-004**: Flannel daemonset fully rolled out (SSM: `kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s`) — proves the 003-11 gate passed and the CNI applied (the downstream effect of the fix)

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Control plane replacement is disruptive (new instance, new IP) | Expected and required — user-data only runs at first boot. The 003-11 per-run signal (instance ID) is designed for this: the new control plane publishes its own ID, and the gate waits for it. Workers re-join via the fresh join command. |
| Replacement cascades (workers must re-join) | The worker bootstrap gates on the same instance-id signal (003-11), so they wait for the new control plane before joining. The join command is re-published by the new control plane's bootstrap. |
| IMDS fetch still fails (network/IMDS issue) | The new guard fails fast with a clear log line (`IMDS fetch failed PRIVATE_IP='...' INSTANCE_ID='...'`) instead of a cryptic `put-parameter` error — easier to diagnose. |
| `set -euxo pipefail` already catches the put-parameter failure | True — but the failure was at the *end* of the script, after a 5-min bootstrap, and the error was easy to miss. The guard moves the failure to the *top* (seconds in) with an explicit message. |
| Plan shows an unexpected replacement | The only force-new change is `user_data`; if the plan shows other replacements, investigate before applying. |
