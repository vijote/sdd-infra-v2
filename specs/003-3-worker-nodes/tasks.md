# Execution Graph (DAG): Worker Nodes + CNI (3-Node Cluster)

**Input**: Design documents from `/specs/003-3-worker-nodes/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~45 min (agent file edits) + CI apply + user-managed SSM verification

---

## Stage 1: Worker Nodes Module

- [x] T001 [Stage 1: Module] Declare Terraform >= 1.5.0, AWS provider >= 5.0.0, and provider config in `terraform/modules/worker-nodes/versions.tf`
- [x] T002 [Stage 1: Module] Define input variables (vpc_id, private_subnet_ids, worker_security_group_id, node_iam_instance_profile_name, control_plane_instance_id) with P2 `validation` blocks in `terraform/modules/worker-nodes/variables.tf`
- [x] T003 [Stage 1: Module] Write worker user-data bootstrap script (install containerd `SystemdCgroup=true`, write `/etc/yum.repos.d/kubernetes.repo` with `gpgcheck=1` + `gpgkey`, `dnf install kubelet/kubeadm/kubectl v1.28.0`, `modprobe br_netfilter` + `/etc/sysctl.d/99-kubernetes.conf` + `sysctl --system`, install AWS CLI, fetch join command from SSM `/sdd-k8s-platform/kubeadm-join-command` with `--with-decryption`, run `kubeadm join`) in `terraform/modules/worker-nodes/bootstrap.sh`
- [x] T004 [Stage 1: Module] Implement `data "aws_ami"` (latest AL2023 x86_64) and 2× `aws_instance` (t2.medium, `private_subnet_ids[1]` and `private_subnet_ids[2]`, no public IP, 20GB gp3 root, worker SG, node instance profile, user-data from `bootstrap.sh`) in `terraform/modules/worker-nodes/main.tf` (Depends on T001, T002, T003)
- [x] T005 [Stage 1: Module] Export output `worker_instance_ids` in `terraform/modules/worker-nodes/outputs.tf` (Depends on T004)

---

## Stage 2: Dev Environment Wiring

- [x] T006 [Stage 2: Dev Env] Add `module "worker_nodes"` instantiation (source `../../modules/worker-nodes`, vpc_id = `module.vpc.vpc_id`, private_subnet_ids = `module.vpc.private_subnet_ids`, worker_security_group_id = `module.cluster_plumbing.worker_security_group_id`, node_iam_instance_profile_name = `module.cluster_plumbing.node_iam_instance_profile_name`, control_plane_instance_id = `module.control_plane.control_plane_instance_id`) in `terraform/environments/dev/main.tf` (Depends on T005)
- [x] T007 [Stage 2: Dev Env] Add `null_resource "apply_flannel_cni"` (SSM `kubectl apply -f kube-flannel.yml` on control plane, `depends_on = [module.worker_nodes]`, poll `get-command-invocation` until `Success`) and root output `worker_instance_ids` in `terraform/environments/dev/main.tf` and `terraform/environments/dev/outputs.tf` (Depends on T006)

---

## Stage 3: Verification (AC-001–AC-003 CI-only; AC-004–AC-007 user-managed SSM — NOT added to terraform-apply.yml)

- [ ] T008 [Stage 3: Verify] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`) (Depends on T007)
- [ ] T009 [Stage 3: Verify] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`) (Depends on T008)
- [ ] T010 [Stage 3: Verify] AC-003: 2 worker EC2 instances running (`aws ec2 describe-instances --instance-ids $(terraform output -raw worker_instance_ids | tr -d '[]"' | tr ',' ' ') --query 'Reservations[].Instances[].State.Name' --output text | grep -c 'running' | grep -q '^2$'`) (Depends on T009)
- [ ] T011 [Stage 3: Verify] AC-004: 3 nodes Ready via SSM Run Command on control plane (`kubectl get nodes --no-headers | grep -c ' Ready' | grep -q '^3$'`) (Depends on T010)
- [ ] T012 [Stage 3: Verify] AC-005: Flannel CNI daemonset rolled out via SSM Run Command on control plane (`kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`) (Depends on T011)
- [ ] T013 [Stage 3: Verify] AC-006: CoreDNS Ready via SSM Run Command on control plane (`kubectl rollout status deployment/coredns -n kube-system --timeout=300s`) (Depends on T012)
- [ ] T014 [Stage 3: Verify] AC-007: all pods Running/Completed via SSM Run Command on control plane (`kubectl get pods -A --no-headers | grep -vE 'Running|Completed' | wc -l | grep -q '^0$'`) (Depends on T013)

---

## Dependencies

```
T001 ─┬─ T004 ─ T005 ─ T006 ─ T007 ─ T008 ─ T009 ─ T010 ─ T011 ─ T012 ─ T013 ─ T014
T002 ─┤
T003 ─┘
```

- **Parallelizable (Stage 1)**: T001, T002, T003 are independent file creations — can be done in any order; T004 depends on all three
- **Sequential (Stage 2)**: T006 → T007 (module must exist before wiring + null_resource)
- **Sequential (Stage 3)**: T008 → T014 (each AC depends on the prior; T008–T010 in CI, T011–T014 user-managed SSM)

## Verification Mappings

| AC | Task | Scope |
|----|------|-------|
| AC-001 | T008 | CI (terraform-apply.yml) |
| AC-002 | T009 | CI (terraform-apply.yml) |
| AC-003 | T010 | CI (terraform-apply.yml) |
| AC-004 | T011 | User-managed SSM Run Command |
| AC-005 | T012 | User-managed SSM Run Command |
| AC-006 | T013 | User-managed SSM Run Command |
| AC-007 | T014 | User-managed SSM Run Command |
