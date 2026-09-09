# Spec: Flannel Per-Run Bootstrap Signal

**Feature Branch**: `003-11-flannel-per-run-bootstrap-signal` | **Date**: 2026-09-09 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Bootstrap script + Terraform provisioner corrections — no new AWS resources, no resource changes
- **Kubernetes Scope**: Control-plane bootstrap (publishes a per-run signal), worker bootstrap (consumes it), Flannel CNI gate
- **AWS Scope**: SSM Parameter Store — one new String parameter `/sdd-k8s-platform/kubeadm-bootstrap-instance-id`
- **Terraform Scope**:
  - `terraform/modules/control-plane/bootstrap.sh` (publish instance-ID param)
  - `terraform/environments/dev/main.tf` (Flannel gate compares instance-ID param)
  - `terraform/modules/worker-nodes/main.tf` (user-data → `replace()` token injection)
  - `terraform/modules/worker-nodes/bootstrap.sh` (consume instance-ID param)

## 2. Problem Statement

The join-command SSM parameter (`/sdd-k8s-platform/kubeadm-join-command`) **persists across
destroy/apply** — it is not a Terraform resource, so `terraform destroy` does not clear it. Each
fresh control plane gets a **new private IP**, so the join command (which embeds the API server
IP) differs per run.

003-8 removed the `delete-parameter` step (correct for a *persistent* control plane) but left the
Flannel gate and the worker bootstrap waiting for the join-command parameter to merely **exist**.
On a **fresh apply** this is a stale-signal race:

1. The previous run's join-command parameter still exists (points to the destroyed control plane's IP).
2. The Flannel gate finds it in ~10s, thinks bootstrap is complete, and sends the Flannel command
   before the new control plane has `kubectl` installed / the API server up → `Failed`.
3. The worker bootstrap `eval`s the stale join command → tries to join the destroyed cluster →
   fails (silent: a user-data failure does not fail the `aws_instance` resource).

**Confirmed by direct probe**: the join-command parameter pointed to `10.0.11.23` (last modified
`16:11:48`), which is a *different, later* control plane than the one that failed
(`i-0beaa7254e698e7f5`). The parameter outlived the control plane that published it.

This is the same stale-signal race 003-7's `delete-parameter` was preventing. 003-8 fixed the
persistent-apply case but broke the fresh-apply case.

## 3. Solution

Make the bootstrap-complete signal **per-run** by publishing the control plane's **instance ID**
to a dedicated parameter, and gating on that parameter **equaling the current control plane
instance ID** (not merely existing). This is correct for both apply types with no delete and no
race:

| Scenario | instance-ID param | Gate behavior |
|----------|-------------------|---------------|
| Fresh apply (new control plane) | stale value = old instance ID ≠ current | blocks until the new bootstrap publishes the current ID |
| Persistent apply (existing control plane) | value already = current ID | returns immediately |

### 3.1 New parameter

- **Name**: `/sdd-k8s-platform/kubeadm-bootstrap-instance-id`
- **Type**: `String` (not sensitive — an instance ID is not a secret)
- **Publisher**: `control-plane/bootstrap.sh`, as the **last** step (after the join-command
  `put-parameter`), so its presence guarantees the join command is also fresh.
- **Value**: the control plane's own instance ID, read from IMDSv2 (same token-based approach as
  the existing private-IP read).

### 3.2 Control plane bootstrap contract

File: `terraform/modules/control-plane/bootstrap.sh`

After the existing join-command `put-parameter` (lines 88-94), add:

```bash
# --- Publish the per-run bootstrap-complete signal (this instance's ID) ---
# The Flannel gate and worker bootstrap wait for this to equal the current control
# plane instance ID, which makes the signal per-run (a stale value from a previous
# run never matches). Published LAST so its presence implies the join command is fresh.
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)
aws ssm put-parameter \
  --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
  --type String \
  --value "${INSTANCE_ID}" \
  --overwrite
```

### 3.3 Flannel gate contract

File: `terraform/environments/dev/main.tf`

Replace the bootstrap-complete wait (currently: poll the join-command param until non-empty) with
a poll of the instance-ID param until it **equals** `$INSTANCE_ID` (already set to
`module.control_plane.control_plane_instance_id` at the top of the provisioner):

```bash
# Wait for bootstrap completion: the control plane bootstrap publishes its own instance ID
# to the bootstrap-instance-id parameter as its LAST step. Waiting for it to equal THIS
# instance's ID makes the signal per-run — a stale value from a previous run never matches,
# so a fresh apply blocks until the new bootstrap finishes, and a persistent apply returns
# immediately.
for i in $(seq 1 60); do
  BOOTSTRAP_ID=$(aws ssm get-parameter \
    --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
    --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
  if [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ]; then
    echo "Control plane bootstrap complete (instance-id signal matches $${INSTANCE_ID})"
    break
  fi
  sleep 10
done
if [ "$${BOOTSTRAP_ID}" != "$${INSTANCE_ID}" ]; then
  echo "Control plane bootstrap did not complete within timeout" >&2
  exit 1
fi
```

The SSM-agent wait, the `send-command`, the KUBECONFIG-prefixed `kubectl apply` (003-9), and the
corrected status-poll query (003-10) are byte-for-byte unchanged.

### 3.4 Worker bootstrap contract

File: `terraform/modules/worker-nodes/bootstrap.sh` + `terraform/modules/worker-nodes/main.tf`

The worker has the same stale-signal bug: it polls for the join-command param to exist, then
`eval`s it. On a fresh apply it `eval`s the stale command. Fix: wait for the instance-ID param to
equal the control plane's instance ID **before** fetching + `eval`ing the join command.

The worker's user-data is a static `file()`, so the control plane instance ID is injected via
`replace()` on a unique literal token (the module already receives `var.control_plane_instance_id`).
**`templatefile` is NOT used**: the bootstrap script is full of bash `${...}` expansions that the
Terraform template engine would try to interpret as expressions, and `%{...}` is template *control*
syntax, not interpolation — both fail.

`worker-nodes/main.tf` (line 37):
```hcl
user_data = replace(file("${path.module}/bootstrap.sh"), "%%CONTROL_PLANE_INSTANCE_ID%%", var.control_plane_instance_id)
```

`worker-nodes/bootstrap.sh` — add the token near the top and gate the join on the instance-ID
param:
```bash
CONTROL_PLANE_INSTANCE_ID="%%CONTROL_PLANE_INSTANCE_ID%%"
BOOTSTRAP_ID_PARAM="/sdd-k8s-platform/kubeadm-bootstrap-instance-id"
# Wait for the control plane's per-run bootstrap signal (its instance ID) to match, so a
# stale join command from a previous run is never eval'd.
for i in $(seq 1 60); do
  BOOTSTRAP_ID=$(aws ssm get-parameter --name "${BOOTSTRAP_ID_PARAM}" \
    --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
  if [ "${BOOTSTRAP_ID}" = "${CONTROL_PLANE_INSTANCE_ID}" ]; then break; fi
  sleep 10
done
if [ "${BOOTSTRAP_ID}" != "${CONTROL_PLANE_INSTANCE_ID}" ]; then
  echo "ERROR: control plane bootstrap signal did not match ${CONTROL_PLANE_INSTANCE_ID} after timeout" >&2
  exit 1
fi
# Now fetch the (fresh) join command and join.
JOIN_COMMAND=$(aws ssm get-parameter --name "${SSM_PARAM_NAME}" --with-decryption \
  --query 'Parameter.Value' --output text)
eval "${JOIN_COMMAND}"
```

## 4. Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Control plane publishes the instance-ID signal (`grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-003: Flannel gate compares the instance-ID param to the current instance (`grep -qF 'BOOTSTRAP_ID}" = "$${INSTANCE_ID}' terraform/environments/dev/main.tf`)
- [ ] AC-004: Worker gates the join on the instance-ID signal (`grep -qF 'kubeadm-bootstrap-instance-id' terraform/modules/worker-nodes/bootstrap.sh`)
- [ ] AC-005: Worker user-data injects the instance ID via `replace()` (`grep -qF 'replace(file("${path.module}/bootstrap.sh")' terraform/modules/worker-nodes/main.tf`)
- [ ] AC-006: `terraform plan -detailed-exitcode` exits 0 (no resource changes; only provisioner + bootstrap + user-data changes)
- [ ] AC-007: Flannel daemonset rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)
- [ ] AC-008: All 3 nodes Ready (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers | grep -c ' Ready'` returns `3`)

## 5. Out of Scope

- No changes to the VPC, cluster-plumbing, or state-backend modules
- No changes to the SSM-agent readiness wait (003-4), the JSON escaping (003-6), the KUBECONFIG prefix (003-9), or the status-poll query (003-10)
- No changes to the Flannel manifest URL or version pin
- No deletion of the join-command parameter (it remains the join source; the instance-ID param is the freshness signal)
