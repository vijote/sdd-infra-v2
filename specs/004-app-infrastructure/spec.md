# Spec: Application Infrastructure

**Feature Branch**: `004-app-infrastructure` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EBS CSI Driver / Storage Classes / Load Balancers / AWS IAM for Service Accounts
- **Kubernetes / Cluster Scope**: Namespaces / NGINX Ingress Controller / cert-manager / Storage Classes
- **Target Services / Modules**: EBS CSI, NGINX Ingress, cert-manager with Let's Encrypt
- **Security & CI/CD**: IRSA for pod-level AWS permissions, TLS certificate automation

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster name"
  default     = "sdd-k8s-platform"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from Phase 1"
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN for IRSA"
}

# Resource / Module Interface
module "application_infrastructure" {
  source = "./src/modules/application-infrastructure"
  
  cluster_name       = var.cluster_name
  vpc_id            = var.vpc_id
  oidc_provider_arn = var.oidc_provider_arn
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "4"
  }
}

# Outputs
output "ebs_csi_controller_role_arn" {
  value       = module.application_infrastructure.ebs_csi_controller_role_arn
  description = "IAM role ARN for EBS CSI controller"
}

output "ingress_controller_service_name" {
  value       = module.application_infrastructure.ingress_controller_service_name
  description = "NGINX Ingress Controller service name"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# Namespace Configuration
apiVersion: v1
kind: Namespace
metadata:
  name: sdd-apps
  labels:
    name: sdd-apps
---
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    name: cert-manager

# StorageClass for EBS gp3
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  fsType: ext4
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer

# NGINX Ingress Controller Helm Values
controller:
  replicaCount: 2
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  ingressClassResource:
    name: nginx
    enabled: true
    default: true
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"

# cert-manager Helm Values
installCRDs: true
replicaCount: 1
webhook:
  replicaCount: 1
cainjector:
  replicaCount: 1
prometheus:
  enabled: false
```

### 1.3 Data & Storage Contracts
- **EBS CSI Driver**: gp3 volumes with 3000 IOPS, 125 MB/s throughput, ext4 filesystem
- **Storage Classes**: ebs-gp3 with Retain policy, WaitForFirstConsumer binding
- **Persistent Volumes**: Dynamic provisioning via CSI driver

### 1.4 Network & Security Contracts
- **NGINX Ingress**: Network Load Balancer (NLB) with internet-facing scheme
- **cert-manager**: Let's Encrypt HTTP-01 challenge for TLS certificates
- **IRSA**: IAM roles for service accounts for EBS CSI controller

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: EBS CSI driver pods running (`kubectl wait --for=condition=Ready pod -l app=ebs-csi-controller -n kube-system --timeout=300s`)
- [ ] AC-002: StorageClass ebs-gp3 available (`kubectl get storageclass ebs-gp3 -o jsonpath='{.provisioner}' | grep -q 'ebs.csi.aws.com'`)
- [ ] AC-003: NGINX Ingress Controller deployed (`helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait --timeout=10m`)
- [ ] AC-004: NLB created for ingress (`kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | grep -E '\.elb\.amazonaws\.com$'`)
- [ ] AC-005: cert-manager installed (`helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true --wait --timeout=10m`)
- [ ] AC-006: Namespaces created (`kubectl create namespace sdd-apps --dry-run=client -o yaml | kubectl apply -f - && kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -`)
- [ ] AC-007: IRSA role working (`kubectl wait --for=condition=Ready pod -l app=ebs-csi-controller -n kube-system --timeout=300s && kubectl exec -n kube-system deployment/ebs-csi-controller -- aws sts get-caller-identity --query 'Account' --output text`)
- [ ] AC-008: IngressClass nginx default (`kubectl get ingressclass nginx -o jsonpath='{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}' | grep -q 'true'`)

## 3. Assumptions & Technical Constraints
- **Storage**: EBS gp3 with default performance settings
- **IAM / Security Boundaries**: IRSA for pod-level AWS permissions, no static credentials
- **Load Balancer**: AWS NLB for ingress controller, no cross-zone load balancing
- **Certificates**: Let's Encrypt for production, rate limits considered
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: Terraform >= 1.5.0, AWS provider >= 5.0.0, Helm >= 3.0.0