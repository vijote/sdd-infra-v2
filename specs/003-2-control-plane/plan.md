# Architecture Delta: Control Plane (kubeadm init)

**Branch**: `003-2-control-plane` | **Date**: 2026-09-05 | **Spec**: specs/003-2-control-plane/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/control-plane/versions.tf` | Create | TF >= 1.5.0, AWS >= 5.0.0, provider config (matches vpc / cluster-plumbing convention) |
| `terraform/modules/control-plane/variables.tf` | Create | `region`, `vpc_id`, `private_subnet_ids`, `control_plane_security_group_id`, `node_iam_instance_profile_name`, `tags` |
| `terraform/modules/control-plane/main.tf` | Create | `data "aws_ami"` (latest AL2023 x86_64), `aws_instance.control_plane` (t2.medium, `private_subnet_ids[0]`, no public IP, 20GB gp3, user-data = bootstrap script) |
| `terraform/modules/control-plane/outputs.tf` | Create | `control_plane_instance_id`, `control_plane_private_ip` |
| `terraform/modules/control-plane/bootstrap.sh` | Create | user-data: install containerd + kubeadm/kubelet/kubectl v1.28.0 → write kubeadm config (cert SANs = private IP + localhost, pod CIDR 192.168.0.0/16, control-plane-endpoints = private IP:6443) → `kubeadm init` → publish join command to SSM `/sdd-k8s-platform/kubeadm-join-command` (SecureString) |
| `terraform/environments/dev/main.tf` | Modify | Add `module "control_plane"` (source `../../modules/control-plane`, consumes `module.vpc` + `module.cluster_plumbing` outputs) |
| `terraform/environments/dev/outputs.tf` | Modify | Add root outputs `control_plane_instance_id`, `control_plane_private_ip` for 003-3 |

## 2. Architectural Boundaries & Dependency Flow

- **Upstream (already deployed)**: 002 (`vpc_id`, `private_subnet_ids`) + 003-1 (`control_plane_security_group_id`, `node_iam_instance_profile_name`) + 003-0-node-role-ssm-permissions (node role can now `ssm:PutParameter`)
- **Bootstrap boundary**: user-data runs **once** at first boot; CI never re-runs `kubeadm init` — it only polls via SSM Run Command
- **SSM control channel**: node publishes the `kubeadm join` command to Parameter Store; 003-3 workers read it (SecureString, `--with-decryption`)
- **AMI source**: spec does not declare an AMI — plan uses `data "aws_ami"` for the latest Amazon Linux 2023 x86_64 (owner 137112412989)
- **Region**: spec's module interface omits it — plan adds `region` var (dev passes `var.region`, populated by the workflow's `TF_VAR_region`), matching every other module

## 3. Provisioning & Rollout Stages

- **Stage 1 — Module (agent)**: create the 5 `terraform/modules/control-plane/` files
- **Stage 2 — Dev wiring (agent)**: add the module block + 2 root outputs to the dev environment
- **Stage 3 — Apply (CI)**: existing `.github/workflows/terraform-apply.yml` on main push launches the instance; user-data bootstraps the cluster
- **Stage 4 — Verification (CI-only)**: AC-003…AC-005 via `aws ssm send-command` + poll `get-command-invocation` until `Success`

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `terraform plan -detailed-exitcode`
- **AC-003**: instance state = `running` (`aws ec2 describe-instances`)
- **AC-004**: control plane node `Ready` (SSM `kubectl wait --for=condition=Ready node --selector=node-role.kubernetes.io/control-plane --timeout=600s`)
- **AC-005**: API server `/healthz` OK (SSM) **and** join command present in SSM (`aws ssm get-parameter --with-decryption | grep 'kubeadm join'`)

## 5. Risks & Mitigations

- **user-data runs once**: a failed bootstrap does not retry — mitigate by keeping the script idempotent-safe and, on failure, replacing the instance (`terraform apply -replace`) or re-running the script via SSM
- **SecureString join command**: workers (003-3) must read with `--with-decryption`; the node role already has `ssm:GetParameter` (003-0-node-role-ssm-permissions)
- **Spec gaps resolved in plan**: `region` var added; AMI via `data "aws_ami"` (AL2023) — no spec change required
- **Verification job**: AC-003…AC-005 are SSM-based and not part of the current `terraform-apply.yml` — they run as a CI verification step (same pattern as prior specs' AC checks)
