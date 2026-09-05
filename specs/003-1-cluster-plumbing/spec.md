# Spec: Cluster Plumbing (Security Groups + IAM)

**Feature Branch**: `003-1-cluster-plumbing` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Security Groups / IAM Roles / IAM Instance Profiles
- **Kubernetes / Cluster Scope**: None (plumbing only — no EC2, no kubeadm)
- **Target Services / Modules**: Terraform module for cluster security groups and node IAM
- **Security & CI/CD**: IAM instance profile with SSM access for future EC2 nodes

### 1.1 Terraform / HCL Resource Contracts

```hcl
# Input Variables
variable "vpc_id" {
  type        = string
  description = "VPC ID from 002-vpc-foundation"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR for security group ingress rules"
  default     = "10.0.0.0/16"
}

# Resource / Module Interface
module "cluster_plumbing" {
  source = "../../modules/cluster-plumbing"

  vpc_id   = var.vpc_id
  vpc_cidr = var.vpc_cidr

  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

# Outputs
output "control_plane_security_group_id" {
  value       = module.cluster_plumbing.control_plane_security_group_id
  description = "Security group ID for control plane nodes"
}

output "worker_security_group_id" {
  value       = module.cluster_plumbing.worker_security_group_id
  description = "Security group ID for worker nodes"
}

output "node_iam_instance_profile_name" {
  value       = module.cluster_plumbing.node_iam_instance_profile_name
  description = "IAM instance profile name for cluster EC2 nodes"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None

### 1.3 Data & Storage Contracts
None

### 1.4 Network & Security Contracts
- **Control Plane SG**: ingress 6443 (kube-apiserver), 2379-2380 (etcd), 22 (SSH via SSM Session Manager) — all from VPC CIDR only; egress all
- **Worker SG**: ingress 10250 (kubelet), 30000-32767 (NodePort), 22 (SSH via SSM) — all from VPC CIDR only; egress all
- **IAM Role**: `AmazonSSMManagedInstanceCore` + `AmazonEC2ContainerRegistryReadOnly` (image pulls)
- **Instance Profile**: attaches the role for EC2 nodes (consumed by 003-2 and 003-3)

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Control plane SG exists with 6443 ingress from VPC CIDR
  ```bash
  aws ec2 describe-security-groups --group-ids $(terraform output -raw control_plane_security_group_id) \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`6443`].CidrIpv4' --output text | grep -q '10.0.0.0/16'
  ```
- [ ] AC-004: Worker SG exists with 30000-32767 ingress from VPC CIDR
  ```bash
  aws ec2 describe-security-groups --group-ids $(terraform output -raw worker_security_group_id) \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`30000`].CidrIpv4' --output text | grep -q '10.0.0.0/16'
  ```
- [ ] AC-005: IAM instance profile exists and attaches a role
  ```bash
  aws iam get-instance-profile --instance-profile-name $(terraform output -raw node_iam_instance_profile_name) \
    --query 'InstanceProfile.Roles[0].Arn' --output text | grep -q 'arn:aws:iam'
  ```
- [ ] AC-006: IAM role has SSM managed policy attached
  ```bash
  ROLE=$(aws iam get-instance-profile --instance-profile-name $(terraform output -raw node_iam_instance_profile_name) \
    --query 'InstanceProfile.Roles[0].RoleName' --output text)
  aws iam list-attached-role-policies --role-name $ROLE \
    --query 'AttachedPolicies[?PolicyName==`AmazonSSMManagedInstanceCore`].PolicyName' --output text | grep -q 'AmazonSSMManagedInstanceCore'
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependency**: `002-vpc-foundation` provides `vpc_id` (and `vpc_cidr` default)
- **Downstream Consumers**: `003-2-control-plane` and `003-3-worker-nodes` consume the SG IDs and instance profile name
- **Security Groups**: Deferred from `002-vpc-foundation` — this spec owns them
- **No EC2**: No instances launched in this phase; only the security/IAM plumbing
- **Testing Policy**: No unit or E2E test generation - validation performed via direct AWS CLI checks in CI/CD
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0
