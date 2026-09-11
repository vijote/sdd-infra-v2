# Spec: IMDS Token Expiry — Bootstrap Instance-ID Publication

**Feature Branch**: `003-13-imds-token-expiry` | **Date**: 2026-09-11 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources)
- **Kubernetes / Cluster Scope**: control-plane bootstrap (EC2 user-data) / SSM Parameter Store signal
- **Target Services / Modules**: `control-plane/bootstrap.sh` (003-2, instance-id step from 003-11)
- **Security & CI/CD**: no CI change — the fix is in the user-data script; existing gates (003-11) unchanged

> **Root cause**: `bootstrap.sh` obtains an IMDSv2 token with a 300s TTL at script start (line 16) and reuses it for the instance-id fetch at the end of the script (line 100). Between those two points, ~5+ minutes of work runs (dnf installs, `kubeadm init`), so the token is **expired** by the time the instance-id is fetched. `curl -s` swallows the 401 → `INSTANCE_ID` is empty → `aws ssm put-parameter` fails with `ValidationException: Member must have length greater than or equal to 1` → the 003-11 bootstrap gate (Flannel + worker) times out after 10 min. The `PRIVATE_IP` fetch (line 18) works because it runs seconds after the token is obtained.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# No Terraform resource changes. The fix is in terraform/modules/control-plane/bootstrap.sh
# (embedded as the control plane's user-data via the 003-2 module).
# The control-plane module's user-data is a file() of bootstrap.sh, so editing the
# .sh file is the only change. A trigger bump on the control-plane resource (or a
# destroy/recreate of the control plane) is required for the new user-data to run —
# user-data only executes at first boot.
```

### 1.2 Bootstrap Script Contract

```bash
# Move the instance-id fetch to the top of the script, alongside PRIVATE_IP,
# while the IMDS token is still fresh (seconds old):
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)

# Guard: fail fast if either value is empty (set -e would catch the put-parameter
# failure anyway, but an explicit check gives a clear log line):
[ -n "${PRIVATE_IP}" ] && [ -n "${INSTANCE_ID}" ] || {
  echo "IMDS fetch failed (PRIVATE_IP='${PRIVATE_IP}' INSTANCE_ID='${INSTANCE_ID}')" >&2
  exit 1
}

# The final publication step (line 100-106) no longer re-fetches — it uses the
# INSTANCE_ID captured at the top (the instance ID is immutable for the instance's
# lifetime, so capturing it early is safe).
```

### 1.3 Data & Storage Contracts
- **SSM Parameter** `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` (String): must equal the current control plane's EC2 instance ID after bootstrap. Consumed by the 003-11 gate (Flannel `apply_flannel_cni` + worker bootstrap).

### 1.4 Network & Security Contracts
- **IMDSv2**: token-based metadata (AL2023 default). Token TTL 300s; the fix ensures both metadata fetches happen within seconds of token acquisition.
- **No new security groups / IAM** (reuses the existing node-role SSM Parameter Store permissions from 003-0-node-role-ssm-permissions).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-004 execute **on the control plane via SSM** — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-004 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Bootstrap instance-id parameter equals the current control plane instance ID
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  PARAM=$(aws ssm get-parameter --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
    --query 'Parameter.Value' --output text)
  [ "$PARAM" = "$IID" ]
  ```
- [ ] AC-004: Flannel daemonset is fully rolled out (proves the 003-11 gate passed and the CNI applied — the downstream effect of the fix)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `003-2-control-plane` (bootstrap.sh), `003-11-flannel-per-run-bootstrap-signal` (the gate this fix unblocks).
- **Downstream Consumer**: `003-12-flannel-cidr-mismatch` (Flannel apply is gated on the instance-id signal; this fix is a prerequisite for 003-12 to work on a fresh apply).
- **User-data only runs at first boot**: the fixed bootstrap.sh takes effect on the **next control plane creation** (destroy + apply, or a forced replacement). A persistent control plane keeps the old user-data — so verification requires a fresh control plane.
- **Instance ID is immutable**: capturing it at script start (instead of at the end) is safe — the EC2 instance ID never changes during the instance's lifetime.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
