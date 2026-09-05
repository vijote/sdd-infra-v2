# Spec: Control Plane (kubeadm init)

**Feature Branch**: `003-2-control-plane` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EC2 Instance (control plane) / Launch Template / User-Data Bootstrap / SSM Parameter Store
- **Kubernetes / Cluster Scope**: kubeadm v1.28.0 / containerd / single control plane node
- **Target Services / Modules**: Terraform module for control plane EC2 + bootstrap scripts
- **Security & CI/CD**: SSM for join-command distribution; SSM Run Command for verification

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

variable "control_plane_security_group_id" {
  type        = string
  description = "Control plane SG from 003-1-cluster-plumbing"
}

variable "node_iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile from 003-1-cluster-plumbing"
}

# Resource / Module Interface
module "control_plane" {
  source = "../../modules/control-plane"

  vpc_id                         = var.vpc_id
  private_subnet_ids             = var.private_subnet_ids
  control_plane_security_group_id = var.control_plane_security_group_id
  node_iam_instance_profile_name = var.node_iam_instance_profile_name

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

# Outputs
output "control_plane_instance_id" {
  value       = module.control_plane.control_plane_instance_id
  description = "Control plane EC2 instance ID"
}

output "control_plane_private_ip" {
  value       = module.control_plane.control_plane_private_ip
  description = "Control plane private IP (API server endpoint)"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
- **kubeadm config** (`/etc/kubeadm/config.yaml`): API server cert SANs = control plane private IP + `localhost`; pod CIDR `192.168.0.0/16`; control plane endpoints = control plane private IP:6443
- **Bootstrap sequence** (user-data, runs once at first boot): install containerd → kubeadm/kubelet/kubectl v1.28.0 → `kubeadm init --config=/etc/kubeadm/config.yaml` → publish join command to SSM Parameter Store. CI does NOT re-run init; it polls until init completes.

### 1.3 Data & Storage Contracts
- **SSM Parameter**: `/sdd-k8s-platform/kubeadm-join-command` (SecureString) — written by control plane user-data after `kubeadm init`; consumed by 003-3 worker bootstrap
- **EBS**: 20GB gp3 root volume (default AMI size)

### 1.4 Network & Security Contracts
- **Instance**: 1× `t2.medium` (2 CPU, 4GB) in `private_subnet_ids[0]`, no public IP
- **kubeadm init**: runs in user-data with `--config=/etc/kubeadm/config.yaml` (no `--skip-phases` — CoreDNS + kube-proxy deploy by default); CI only polls for completion
- **Flannel CNI**: NOT deployed in this phase (deferred to `003-3-worker-nodes` with the workers)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-003 through AC-005 execute **on the control plane via SSM** (`aws ssm send-command` + poll `aws ssm get-command-invocation` until `Status` = `Success`) — no public API endpoint, no kubeconfig in CI.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Control plane EC2 instance running
  ```bash
  aws ec2 describe-instances --instance-ids $(terraform output -raw control_plane_instance_id) \
    --query 'Reservations[0].Instances[0].State.Name' --output text | grep -q 'running'
  ```
- [ ] AC-004: kubeadm init completed (control plane node Ready)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl wait --for=condition=Ready node --selector=node-role.kubernetes.io/control-plane --timeout=600s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 60); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: API server healthy and join command published to SSM
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["sudo kubectl get --raw /healthz"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 10); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  aws ssm get-parameter --name /sdd-k8s-platform/kubeadm-join-command --with-decryption \
    --query 'Parameter.Value' --output text | grep -q 'kubeadm join'
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `002-vpc-foundation` (vpc_id, private_subnet_ids) + `003-1-cluster-plumbing` (control plane SG, instance profile)
- **Downstream Consumer**: `003-3-worker-nodes` consumes the SSM join command + control plane private IP
- **Single Control Plane**: 1 node, no HA (dev environment)
- **Bootstrap via user-data**: containerd + kubeadm v1.28.0 installed at first boot; `kubeadm init` runs once
- **Testing Policy**: No unit or E2E test generation - validation performed via direct AWS CLI + SSM checks in CI/CD
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0
