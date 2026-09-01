# Spec: [FEATURE_NAME]

**Feature Branch**: `[###-feature-name]` | **Date**: [DATE] | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: [AWS VPC / Subnets / Security Groups / EC2 / ASG / IAM / Storage / Route53 DNS]
- **Kubernetes / Cluster Scope**: [kubeadm control-plane / worker nodes / Flannel CNI / EBS CSI / Helm releases]
- **Target Services / Modules**: [cert-manager, MySQL, NGINX Ingress Controller, CoreDNS, Cluster Autoscaler]
- **Security & CI/CD**: [GitHub OIDC trust, AWS Secrets Manager, CloudFormation IAM roles]

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "[var_name]" {
  type        = [string | number | bool | list(...) | map(...)]
  description = "[Explicit technical purpose]"
  default     = [default_value]
}

# Resource / Module Interface
module "[module_name]" {
  source = "[./modules/...]"
  # inputs
}

# Outputs
output "[output_name]" {
  value       = [resource.attribute]
  description = "[Exported value for downstream dependencies]"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# Helm Values / Manifest Contract
apiVersion: [api_version]
kind: [ResourceKind | HelmRelease]
metadata:
  name: [resource-name]
  namespace: [namespace]
spec:
  # Exact configuration specs (replicas, storageClass, cert-manager ClusterIssuer, MySQL credentials ref, Flannel CNI backend)
```

### 1.3 Data & Storage Contracts
- **StorageClass / PersistentVolumes**: [e.g., EBS gp3 CSI Driver, retain policy, accessMode: ReadWriteOnce]
- **Database / Schema Migrations**: [e.g., MySQL 8.0, initial DDL/migrations path, Secret refs for credentials]
- **DNS / Route53**: [Hosted zone IDs, record types (A/CNAME/TXT), TTL values, health checks]

### 1.4 Network & Security Contracts
- **Flannel CNI Configuration**: [VXLAN backend, network CIDR, VNI, Port]
- **NGINX Ingress Controller**: [Controller class, TLS termination, annotations, load balancer type]
- **Security Groups**: [Ingress/egress rules for control-plane (6443), SSH (22), worker node communication]

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Terraform syntax & formatting validation passes (`terraform fmt -check && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resource delta without errors (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Kubernetes manifests & Helm values pass linting (`helm lint [path]` / `kubectl apply --dry-run=client -k [path]`)
- [ ] AC-004: Node & control plane readiness verified via kubeadm/kubectl (`kubectl get nodes -o wide` returns Ready)
- [ ] AC-005: Addon pods and controllers achieve Healthy status (`kubectl wait --namespace [ns] --for=condition=Ready pod -l app=[app] --timeout=120s`)
- [ ] AC-006: cert-manager Certificate reaches Ready state (`kubectl get certificate [cert-name] -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`)
- [ ] AC-007: MySQL connectivity check passes (`kubectl exec [mysql-pod] -- mysqladmin ping -u root -p"$MYSQL_ROOT_PASSWORD"`)

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: [VPC CIDR: 10.0.0.0/16, Pod CIDR: 192.168.0.0/16, Service CIDR: 10.96.0.0/12]
- **IAM / Security Boundaries**: [Least-privilege IAM instance profile for control plane / workers]
- **Storage / Backup Boundaries**: [EBS CSI volume snapshots or backup retention policy]
- **External Prerequisites**: [Any AWS resources, roles, or configurations that must be created manually before Terraform execution]
- **Circular Dependency Prevention**: [Resources required by Terraform must be provisioned externally (e.g., via CloudFormation, AWS Console, or AWS CLI)]
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
