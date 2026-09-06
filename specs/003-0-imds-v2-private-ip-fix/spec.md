# Spec: IMDSv2 Private IP Fix

**Feature Branch**: `003-0-imds-v2-private-ip-fix` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Bootstrap script correction only — no new AWS resources, no Terraform resource changes
- **Kubernetes / Cluster Scope**: Control plane node bootstrap (003-2-control-plane)
- **Target Service**: `terraform/modules/control-plane/bootstrap.sh` (EC2 user-data, runs once at first boot)
- **Root Cause (fatal)**: Line 16 fetches the private IP with a bare `curl -s http://169.254.169.254/latest/meta-data/local-ipv4`. AL2023 enforces **IMDSv2** (token-based) by default, so the unauthenticated request returns 401 and `curl -s` swallows it — `PRIVATE_IP` is empty. `kubeadm init` then renders `controlPlaneEndpoint: :6443` and fails with `hostport :6443: host '' must be a valid IP address or a valid RFC-1123 DNS subdomain`.
- **Root Cause (warning)**: Line 68 declares the KubeletConfiguration document with `apiVersion: kubeadm.k8s.io/v1beta3`. That GVK is wrong — `KubeletConfiguration` belongs to `kubelet.k8s.io/v1beta1`. kubeadm logs `WARNING: Ignored YAML document ... Kind=KubeletConfiguration` and silently drops the `cgroupDriver: systemd` block.
- **Decision**: (1) Request an IMDSv2 session token and pass it on the metadata call so `PRIVATE_IP` resolves. (2) Correct the KubeletConfiguration `apiVersion` to `kubelet.k8s.io/v1beta1` so the cgroup driver config is honored and the warning disappears.

### 1.1 Bootstrap Script Contract

File: `terraform/modules/control-plane/bootstrap.sh`

**Fix A — IMDSv2 private IP (replace line 16):**

```bash
# --- Detect private IP via IMDSv2 (AL2023 enforces token-based metadata) ---
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)
```

- **Line 17** (`echo "Control plane private IP: ${PRIVATE_IP}"`): unchanged — now prints a real IP
- **All `${PRIVATE_IP}` consumers** (lines 49, 58, 64): unchanged — now receive a valid value

**Fix B — KubeletConfiguration GVK (replace line 68):**

```bash
apiVersion: kubelet.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

- **Lines 46, 55** (`apiVersion: kubeadm.k8s.io/v1beta3` for InitConfiguration and ClusterConfiguration): unchanged — those GVKs are correct
- **All other lines**: unchanged (containerd, kubernetes repo, AWS CLI install, `kubeadm init`, SSM publish)
- **No Terraform changes**: the module's `main.tf` already references `bootstrap.sh` via `user_data = file("${path.module}/bootstrap.sh")`; only the script content changes

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: `user_data` is a computed attribute of the instance; changing `bootstrap.sh` changes the `user_data` hash, forcing **replacement** of the control plane instance (destroy + re-launch). The new instance re-runs the corrected bootstrap at first boot
- **Rollback**: Revert the `bootstrap.sh` change and re-apply (instance replaced again)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: IMDSv2 token is requested (`grep -q 'X-aws-ec2-metadata-token-ttl-seconds' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-003: The metadata call passes the token (`grep -q 'X-aws-ec2-metadata-token: ${IMDS_TOKEN}' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-004: KubeletConfiguration uses the correct GVK (`grep -q 'apiVersion: kubelet.k8s.io/v1beta1' terraform/modules/control-plane/bootstrap.sh`)
- [ ] AC-005: Join command published to SSM after re-launch (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`)

## 3. Assumptions & Constraints

- **Scope**: Two-line-class fixes to the bootstrap script; no change to instance type, subnet, IAM, or kubeadm version (stays v1.28.0)
- **IMDSv2 is the AL2023 default**: the token-based flow works whether the instance is set to `optional` or `required` mode; no `ec2metadata` service setting change is needed
- **Instance replacement**: because `user_data` is embedded in the instance, the fix requires the control plane instance to be destroyed and re-launched — expected and acceptable in the dev up/down test loop
- **KubeletConfiguration GVK**: `kubelet.k8s.io/v1beta1` is the correct group/version for kubeadm v1.28; the `cgroupDriver: systemd` value is redundant with the containerd `SystemdCgroup = true` setting but is now actually honored (removes the warning)
- **Ordering**: This spec MUST be applied before 003-2's control plane is considered healthy; the join command (AC-005) is the end-to-end proof the corrected bootstrap ran to completion
