# Execution Graph (DAG): Control Plane (kubeadm init)

**Input**: Design documents from `/specs/003-2-control-plane/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~45 min (agent file edits) + CI apply + SSM verification

---

## Stage 1: Control Plane Module

- [x] T001 [Stage 1: Module] Declare Terraform >= 1.5.0, AWS provider >= 5.0.0, and provider config in `terraform/modules/control-plane/versions.tf`
- [x] T002 [Stage 1: Module] Define input variables (region, vpc_id, private_subnet_ids, control_plane_security_group_id, node_iam_instance_profile_name, tags) in `terraform/modules/control-plane/variables.tf`
- [x] T003 [Stage 1: Module] Write user-data bootstrap script (install containerd + kubeadm/kubelet/kubectl v1.28.0, write kubeadm config with cert SANs = private IP + localhost / pod CIDR 192.168.0.0/16 / control-plane-endpoints = private IP:6443, run `kubeadm init`, publish join command to SSM `/sdd-k8s-platform/kubeadm-join-command` SecureString) in `terraform/modules/control-plane/bootstrap.sh`
- [x] T004 [Stage 1: Module] Implement `data "aws_ami"` (latest AL2023 x86_64) and `aws_instance.control_plane` (t2.medium, `private_subnet_ids[0]`, no public IP, 20GB gp3 root, control plane SG, node instance profile, user-data from `bootstrap.sh`) in `terraform/modules/control-plane/main.tf` (Depends on T001, T002, T003)
- [x] T005 [Stage 1: Module] Export outputs (control_plane_instance_id, control_plane_private_ip) in `terraform/modules/control-plane/outputs.tf` (Depends on T004)

---

## Stage 2: Dev Environment Wiring

- [x] T006 [Stage 2: Dev Env] Add `module "control_plane"` instantiation (source `../../modules/control-plane`, region = `var.region`, vpc_id = `module.vpc.vpc_id`, private_subnet_ids = `module.vpc.private_subnet_ids`, control_plane_security_group_id = `module.cluster_plumbing.control_plane_security_group_id`, node_iam_instance_profile_name = `module.cluster_plumbing.node_iam_instance_profile_name`) in `terraform/environments/dev/main.tf` (Depends on T005)
- [x] T007 [Stage 2: Dev Env] Add root outputs (control_plane_instance_id, control_plane_private_ip) for 003-3 in `terraform/environments/dev/outputs.tf` (Depends on T006)

---

## Stage 3: Verification (CI-only — executed in GitHub Actions, never locally)

- [ ] T008 [Stage 3: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T007)
- [ ] T009 [Stage 3: Verify] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`) (Depends on T008)
- [ ] T010 [Stage 3: Verify] AC-003: Control plane EC2 instance running (`aws ec2 describe-instances --instance-ids $(terraform output -raw control_plane_instance_id) --query 'Reservations[0].Instances[0].State.Name' --output text | grep -q 'running'`) (Depends on T009)
- [ ] T011 [Stage 3: Verify] AC-004: kubeadm init completed — control plane node Ready via SSM (`kubectl wait --for=condition=Ready node --selector=node-role.kubernetes.io/control-plane --timeout=600s`, poll `get-command-invocation` until `Success`) (Depends on T010)
- [ ] T012 [Stage 3: Verify] AC-005: API server `/healthz` OK via SSM AND join command published (`aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption --query 'Parameter.Value' --output text | grep -q 'kubeadm join'`) (Depends on T011)

---

## Dependencies / Execution Order

```
T001 ─┐
      ├─ T004 ─ T005 ─ T006 ─ T007 ─ T008 ─ T009 ─ T010 ─ T011 ─ T012
T002 ─┤
T003 ─┘
```

- **Parallelizable**: T001, T002, T003 (independent module scaffolding)
- **Sequential**: T004 → T005 → T006 → T007 (instance → outputs → wiring chain)
- **CI chain**: T008 → T009 → T010 → T011 → T012 (SSM verification is strictly sequential — each gate depends on the previous state)

## Notes

- **1:1 file mapping**: T001–T007 each touch exactly one file (constitution DAG principle)
- **Bootstrap runs once**: user-data executes at first boot only; CI never re-runs `kubeadm init` — it polls via SSM Run Command
- **Deployment**: applied by the existing `.github/workflows/terraform-apply.yml` on main push — no local apply (constitution principles 5, 6, 8)
- **Verification**: Stage 3 tasks run in GitHub Actions CI only (constitution principles 5, 6, 8) — never locally
- **Downstream**: 003-3-worker-nodes consumes `control_plane_private_ip` + the SSM join command (SecureString, read with `--with-decryption`)
