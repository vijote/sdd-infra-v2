# Spec: Worker Nodes + CNI (3-Node Cluster)

**Feature Branch**: `003-3-worker-nodes` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EC2 Instances (2 workers) / Launch Templates / User-Data Bootstrap / Flannel CNI
- **Kubernetes / Cluster Scope**: worker join / Flannel CNI (VXLAN) / CoreDNS readiness / 3-node cluster
- **Target Services / Modules**: Terraform module for worker EC2 + CNI deployment
- **Security & CI/CD**: SSM for join-command retrieval; SSM Run Command for verification

### 1.1 Terraform / HCL Resource Contracts

```hcl
# Input Variables
variable "vpc_id" {
  type        = string
  description = "VPC ID from 002-vpc-foundation"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from 002-vpc-foundation"
}

variable "worker_security_group_id" {
  type        = string
  description = "Worker SG from 003-1-cluster-plumbing"
}

variable "node_iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile from 003-1-cluster-plumbing"
}

variable "control_plane_instance_id" {
  type        = string
  description = "Control plane instance ID from 003-2-control-plane (CNI applied here)"
}

# Resource / Module Interface
module "worker_nodes" {
  source = "../../modules/worker-nodes"

  vpc_id                         = var.vpc_id
  private_subnet_ids             = var.private_subnet_ids
  worker_security_group_id       = var.worker_security_group_id
  node_iam_instance_profile_name = var.node_iam_instance_profile_name
  control_plane_instance_id      = var.control_plane_instance_id

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

# Flannel CNI — version-controlled, re-runnable (P7 Immutable Deployment)
# Applied on the control plane via SSM after workers join; idempotent (kubectl apply).
resource "null_resource" "apply_flannel_cni" {
  depends_on = [module.worker_nodes]
  triggers   = { control_plane_instance_id = var.control_plane_instance_id }

  provisioner "local-exec" {
    command = <<-EOT
      CID=$(aws ssm send-command --instance-ids ${var.control_plane_instance_id} \
        --document-name AWS-RunShellScript \
        --parameters 'commands=["sudo kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"]' \
        --query 'Command.CommandId' --output text)
      for i in $(seq 1 30); do
        S=$(aws ssm get-command-invocation --command-id $CID --instance-id ${var.control_plane_instance_id} --query 'Status' --output text)
        [ "$S" = "Success" ] && break; sleep 10
      done
      [ "$S" = "Success" ]
    EOT
  }
}

# Outputs
output "worker_instance_ids" {
  value       = module.worker_nodes.worker_instance_ids
  description = "Worker EC2 instance IDs"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
- **Worker bootstrap** (user-data, runs once at first boot) — a worker runs kubelet, so it needs the **same node prerequisites** the control plane required (see `003-0-kubeadm-repo-gpg-fix` + `003-0-kubeadm-preflight-sysctl-fix`):
  1. install containerd (`SystemdCgroup = true`)
  2. write `/etc/yum.repos.d/kubernetes.repo` with `gpgcheck=1` + `gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key` (AL2023 gotcha: `dnf config-manager --add-repo` omits `gpgkey` → `GPG check FAILED`)
  3. `dnf install kubelet/kubeadm/kubectl v1.28.0`
  4. `modprobe br_netfilter` + `/etc/sysctl.d/99-kubernetes.conf` (`net.bridge.bridge-nf-call-iptables=1`, `net.bridge.bridge-nf-call-ip6tables=1`, `net.ipv4.ip_forward=1`) + `sysctl --system`
  5. install AWS CLI → fetch join command from SSM Parameter `/sdd-k8s-platform/kubeadm-join-command` (SecureString, `--with-decryption`) → `kubeadm join`
  - **No IMDSv2 private-IP fetch needed** — the join command already carries the control plane endpoint
- **Flannel CNI**: `kube-flannel.yml` (VXLAN backend, VNI 4096, port 4789 UDP, network `192.168.0.0/16`) — applied **on the control plane** after workers join, via a version-controlled `null_resource` (see 1.1), NOT only inside a verification AC
- **Deployment order**: workers join (NotReady until CNI) → apply Flannel on control plane → all nodes Ready → CoreDNS Ready

### 1.3 Data & Storage Contracts
- **SSM Parameter**: `/sdd-k8s-platform/kubeadm-join-command` (SecureString) — read by worker user-data (written by 003-2)
- **EBS**: 20GB gp3 root volume per worker

### 1.4 Network & Security Contracts
- **Instances**: 2× `t2.small` (1 CPU, 2GB) in `private_subnet_ids[1]` and `private_subnet_ids[2]` (distinct AZs), no public IP
- **Flannel VXLAN**: UDP 4789 between nodes (allowed by worker SG VPC-CIDR ingress)
- **NodePort range**: 30000-32767 (worker SG)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-004 through AC-007 execute **on the control plane via SSM** (`aws ssm send-command` + poll `aws ssm get-command-invocation` until `Status` = `Success`) — no public API endpoint, no kubeconfig in CI.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: 2 worker EC2 instances running
  ```bash
  aws ec2 describe-instances --instance-ids $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') \
    --query 'Reservations[*].Instances[*].State.Name' --output text | grep -c 'running' | grep -q '^2$'
  ```
- [ ] AC-004: 2 worker nodes joined cluster
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl get nodes -l node-role.kubernetes.io/worker --no-headers | wc -l"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  aws ssm get-command-invocation --command-id $CID --instance-id $IID \
    --query 'StandardOutputContent' --output text | grep -q '^2$'
  ```
- [ ] AC-005: Flannel CNI deployed on control plane (applied by the version-controlled `null_resource.apply_flannel_cni`; this AC only verifies the daemonset is rolled out)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-006: All 3 nodes in Ready state
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl wait --for=condition=Ready nodes --all --timeout=600s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 60); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-007: CoreDNS pods ready
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `002-vpc-foundation` (vpc_id, private_subnet_ids) + `003-1-cluster-plumbing` (worker SG, instance profile) + `003-2-control-plane` (control plane instance ID, SSM join command)
- **Downstream Consumer**: `004-app-infrastructure` (ingress, workloads) consumes the Ready 3-node cluster
- **CNI after join**: workers are NotReady until Flannel is applied; AC-004 (joined) precedes AC-005 (CNI) precedes AC-006 (Ready)
- **Testing Policy**: No unit or E2E test generation - validation performed via direct AWS CLI + SSM checks in CI/CD
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0
