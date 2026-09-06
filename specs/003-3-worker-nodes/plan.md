# Architecture Delta: Worker Nodes + CNI (3-Node Cluster)

**Branch**: `003-3-worker-nodes` | **Date**: 2026-09-05 | **Spec**: specs/003-3-worker-nodes/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/worker-nodes/versions.tf` | Create | TF >= 1.5.0, AWS provider >= 5.0.0, provider config (matches `vpc`/`control-plane` module convention) |
| `terraform/modules/worker-nodes/variables.tf` | Create | 5 inputs (vpc_id, private_subnet_ids, worker_security_group_id, node_iam_instance_profile_name, control_plane_instance_id) with P2 validation blocks |
| `terraform/modules/worker-nodes/main.tf` | Create | 2× `aws_instance` (t2.medium, `private_subnet_ids[1]`/`[2]`, no public IP, node instance profile, worker SG) + `user_data` from `bootstrap.sh` |
| `terraform/modules/worker-nodes/bootstrap.sh` | Create | Worker bootstrap: containerd → GPG repo file → kubelet/kubeadm/kubectl v1.28.0 → br_netfilter + sysctls → AWS CLI → fetch join command from SSM → `kubeadm join` |
| `terraform/modules/worker-nodes/outputs.tf` | Create | `worker_instance_ids` |
| `terraform/environments/dev/main.tf` | Modify | Add `module "worker_nodes"` (wired to `module.vpc`/`module.cluster_plumbing`/`module.control_plane` outputs) + `null_resource "apply_flannel_cni"` (SSM `kubectl apply` on control plane, `depends_on = [module.worker_nodes]`) |
| `terraform/environments/dev/outputs.tf` | Modify | Add root output `worker_instance_ids` |

**No other files change.** No CloudFormation, no IAM change (node role already has `ssm:GetParameter` from `003-0-node-role-ssm-permissions`), no workflow change.

## 2. Architectural Boundaries & Dependency Flow

- **Boundary**: New `worker-nodes` Terraform module + dev-environment wiring + a `null_resource` for the CNI. No new AWS IAM, no new VPC resources, no new workflow
- **Consumes (upstream outputs)**:
  - `002-vpc-foundation` → `vpc_id`, `private_subnet_ids` (workers use `[1]` and `[2]` — distinct AZs)
  - `003-1-cluster-plumbing` → `worker_security_group_id`, `node_iam_instance_profile_name`
  - `003-2-control-plane` → `control_plane_instance_id` (CNI applied here) + the join command in SSM Parameter Store
- **Worker bootstrap** (runs once at first boot, mirrors the control plane's node prerequisites):
  1. containerd (`SystemdCgroup = true`)
  2. `/etc/yum.repos.d/kubernetes.repo` with `gpgcheck=1` + `gpgkey` (AL2023 GPG gotcha)
  3. `dnf install kubelet/kubeadm/kubectl v1.28.0`
  4. `modprobe br_netfilter` + `/etc/sysctl.d/99-kubernetes.conf` + `sysctl --system` (preflight gotcha)
  5. AWS CLI → `aws ssm get-parameter --with-decryption` (join command) → `kubeadm join`
  - **No IMDSv2 private-IP fetch** — the join command already carries the control plane endpoint
- **Flannel CNI**: applied on the control plane via SSM by `null_resource.apply_flannel_cni` (version-controlled, idempotent `kubectl apply`) — P7 Immutable Deployment
- **Deployment order**: workers join (NotReady until CNI) → Flannel applied on control plane → all 3 nodes Ready → CoreDNS Ready
- **Instance replacement**: `user_data` is embedded in each worker instance; a `bootstrap.sh` change forces worker replacement (destroy + re-launch)

## 3. Provisioning & Rollout Stages

- **Stage 1 — Module (agent)**: Create the 5 `worker-nodes` module files (versions, variables, main, bootstrap.sh, outputs)
- **Stage 2 — Dev wiring (agent)**: Add `module "worker_nodes"` + `null_resource "apply_flannel_cni"` to `dev/main.tf`; add `worker_instance_ids` to `dev/outputs.tf`
- **Stage 3 — Apply (CI)**: Push/merge triggers existing `.github/workflows/terraform-apply.yml`; 2 workers launch, bootstrap runs, workers join; `null_resource` applies Flannel on the control plane via SSM
- **Stage 4 — Verify (user-managed, P6)**: AC-001–AC-003 run in CI; AC-004–AC-007 (SSM Run Command: 3 nodes Ready, Flannel rollout, CoreDNS Ready, pods Running) are executed by the user after apply — **NOT** added to `terraform-apply.yml`

## 4. Verification Gates (AC-001–AC-003 in CI; AC-004–AC-007 user-managed)

- **AC-001** (CI): `terraform fmt -check -recursive && terraform validate`
- **AC-002** (CI): `terraform plan -detailed-exitcode`
- **AC-003** (CI): 2 worker instances running (`aws ec2 describe-instances` on `worker_instance_ids`)
- **AC-004** (user): 3 nodes Ready via SSM `kubectl get nodes`
- **AC-005** (user): Flannel daemonset rolled out via SSM `kubectl rollout status`
- **AC-006** (user): CoreDNS Ready via SSM `kubectl rollout status`
- **AC-007** (user): all pods Running/Completed via SSM `kubectl get pods -A`

## 5. Risks & Mitigations

- **`null_resource` timing**: `depends_on = [module.worker_nodes]` completes when instances are *created*, not when they've *joined*. The Flannel `kubectl apply` may run before workers are Ready — acceptable, because the Flannel daemonset schedules on nodes as they become Ready. The CNI apply itself only needs the control plane API server (already up from 003-2)
- **`local-exec` runs on the CI runner**: the `null_resource` provisioner executes on the GitHub Actions runner (which has the assumed-role AWS credentials), not on the control plane — it only issues the SSM `send-command`; the actual `kubectl apply` runs on the control plane instance
- **Worker bootstrap mirrors control-plane gotchas**: the GPG repo + br_netfilter/sysctl fixes are baked in from the start (learned from `003-0-kubeadm-repo-gpg-fix` + `003-0-kubeadm-preflight-sysctl-fix`), so workers should not repeat those failures
- **P6 verification scope**: AC-004–AC-007 are user-managed SSM Run Command checks — explicitly excluded from `terraform-apply.yml` to avoid new CI jobs and local/agent tooling
- **P2 constraints**: all 5 inputs carry `validation` blocks; bad upstream values fail at plan time, not apply time
- **Rollback**: `terraform destroy` of the worker-nodes module + `null_resource` removes the 2 workers and (idempotently) leaves the control plane intact
