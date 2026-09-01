# Spec: kubeadm Compute Cluster

**Feature Branch**: `003-compute-cluster` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EC2 Instances / Launch Templates / Auto Scaling Groups / IAM Instance Profiles / SSM Parameter Store
- **Kubernetes / Cluster Scope**: kubeadm v1.28.0 / containerd / Flannel CNI / kubelet configuration
- **Target Services / Modules**: Control plane (1 node), Worker nodes (2 nodes), Bootstrap scripts
- **Security & CI/CD**: IAM roles for EC2, SSM for secure join command distribution

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
  default     = "v1.28.0"
}

variable "control_plane_instance_type" {
  type        = string
  description = "EC2 instance type for control plane"
  default     = "t2.medium"
}

variable "worker_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes"
  default     = "t2.small"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from Phase 1"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs from Phase 1"
}

variable "control_plane_security_group_id" {
  type        = string
  description = "Security group ID for control plane"
}

variable "worker_security_group_id" {
  type        = string
  description = "Security group ID for worker nodes"
}

# Resource / Module Interface
module "kubernetes_cluster" {
  source = "./src/modules/kubernetes-cluster"
  
  kubernetes_version              = var.kubernetes_version
  control_plane_instance_type    = var.control_plane_instance_type
  worker_instance_type           = var.worker_instance_type
  vpc_id                         = var.vpc_id
  private_subnet_ids             = var.private_subnet_ids
  control_plane_security_group_id = var.control_plane_security_group_id
  worker_security_group_id       = var.worker_security_group_id
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "3"
  }
}

# Outputs
output "control_plane_private_ip" {
  value       = module.kubernetes_cluster.control_plane_private_ip
  description = "Control plane private IP for API server endpoint"
}

output "worker_node_ids" {
  value       = module.kubernetes_cluster.worker_node_ids
  description = "Worker node EC2 instance IDs"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# kubeadm Configuration API
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "{{ CONTROL_PLANE_IP }}"
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    cgroup-driver: systemd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "{{ CONTROL_PLANE_IP }}:6443"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "192.168.0.0/16"
  dnsDomain: "cluster.local"
apiServer:
  certSANs:
  - "{{ CONTROL_PLANE_IP }}"
  - "localhost"
  - "127.0.0.1"
  extraArgs:
    service-node-port-range: "30000-32767"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: KubeletConfiguration
cgroupDriver: systemd
serverTLSBootstrap: true
rotateCertificates: true
```

### 1.3 Data & Storage Contracts
- **SSM Parameters**: Secure storage for kubeadm join command with encryption
- **EC2 User Data**: Bootstrap scripts for control plane initialization and worker join
- **Containerd Configuration**: SystemdCgroup = true for Kubernetes compatibility

### 1.4 Network & Security Contracts
- **Flannel CNI**: VXLAN backend, VNI 4096, Port 4789 UDP, Network: 192.168.0.0/16
- **API Server**: TLS certificate includes all control plane IPs and localhost
- **IAM Roles**: EC2 instances with SSM access and basic AWS permissions

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Control plane EC2 instance running (`aws ec2 describe-instances --instance-ids $(terraform output -raw control_plane_instance_id) --query 'Reservations[0].Instances[0].State.Name' --output text | grep -q 'running'`)
- [ ] AC-002: Worker EC2 instances running (`aws ec2 describe-instances --instance-ids $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') --query 'Reservations[*].Instances[*].State.Name' --output text | grep -c 'running' | grep -q '^2$'`)
- [ ] AC-003: kubeadm init completed on control plane (`aws ssm send-command --instance-ids $(terraform output -raw control_plane_instance_id) --document-name "AWS-RunShellScript" --parameters 'commands=["sudo kubeadm init --config=/etc/kubeadm/config.yaml --skip-phases=addon/all"]' --query 'Command.CommandId' --output text && sleep 30 && aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $(terraform output -raw control_plane_instance_id) --query 'Status' --output text | grep -q 'Success'`)
- [ ] AC-004: Flannel CNI deployed (`kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml && kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s`)
- [ ] AC-005: Nodes in Ready state (`kubectl wait --for=condition=Ready nodes --all --timeout=600s && kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c 'True' | grep -q '^3$'`)
- [ ] AC-006: API server accessible (`kubectl get componentstatuses 2>/dev/null || kubectl get apiservices | grep -v 'False'`)
- [ ] AC-007: Worker nodes joined cluster (`kubectl get nodes -l node-role.kubernetes.io/worker --no-headers | wc -l | grep -q '^2$'`)
- [ ] AC-008: CoreDNS pods running (`kubectl wait --for=condition=Ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s`)

## 3. Assumptions & Technical Constraints
- **Kubernetes Version**: Hardcoded to v1.28.0 as specified in requirements
- **Instance Types**: t2.medium for control plane (2 CPU, 4GB RAM), t2.small for workers (1 CPU, 2GB RAM)
- **IAM / Security Boundaries**: EC2 instances with least-privilege IAM roles
- **Storage / Backup Boundaries**: EBS volumes with default retention, etcd backups not configured in this phase
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0