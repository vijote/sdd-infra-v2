# Spec: Operational Tooling

**Feature Branch**: `007-ops-tooling` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Shell Scripts / GitHub Actions / Validation Commands / Monitoring Setup
- **Kubernetes / Cluster Scope**: kubectl configs / Helm deployments / Health checks
- **Target Services / Modules**: Deployment automation, validation scripts, operational procedures
- **Security & CI/CD**: Automated validation, rollback procedures, access controls

### 1.1 Terraform / HCL Resource Contracts
```hcl
# Input Variables / Schema
variable "cluster_name" {
  type        = string
  description = "Kubernetes cluster name"
  default     = "sdd-k8s-platform"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

# Resource / Module Interface
module "operational_tooling" {
  source = "./src/modules/operational-tooling"
  
  cluster_name = var.cluster_name
  region       = var.region
  
  tags = {
    Project = "sdd-k8s-platform"
    Phase   = "7"
  }
}

# Outputs
output "deployment_script_path" {
  value       = module.operational_tooling.deployment_script_path
  description = "Path to deployment automation script"
}

output "validation_script_path" {
  value       = module.operational_tooling.validation_script_path
  description = "Path to cluster validation script"
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
None for Phase 7 (tooling and scripts only)

### 1.3 Data & Storage Contracts
- **Scripts Location**: All operational scripts in src/scripts/ directory
- **Configuration Files**: kubeconfig, helm values, validation parameters

### 1.4 Network & Security Contracts
- **Access Control**: Scripts use IAM roles and kubeconfig for authentication
- **Validation**: Automated health checks and connectivity tests

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Deployment script executable (`test -x src/scripts/deploy.sh && src/scripts/deploy.sh --help | grep -q 'Usage'`)
- [ ] AC-002: Validation script runs (`src/scripts/validate-cluster.sh --region us-east-1 --dry-run && echo $? | grep -q '0'`)
- [ ] AC-003: kubectl access configured (`kubectl get nodes --no-headers | wc -l | grep -q '^3$'`)
- [ ] AC-004: Helm releases deployed (`helm list -n sdd-apps --filter 'status=deployed' --output json | jq -r '.[] | .name' | wc -l | grep -v '^0$'`)
- [ ] AC-005: Health checks pass (`src/scripts/health-check.sh --all-services --timeout 60 && echo $? | grep -q '0'`)
- [ ] AC-006: Backup script functional (`src/scripts/backup-mysql.sh --dry-run --validate && echo $? | grep -q '0'`)
- [ ] AC-007: Rollback script available (`test -x src/scripts/rollback.sh && src/scripts/rollback.sh --help | grep -q 'Usage'`)
- [ ] AC-008: Monitoring endpoints accessible (`kubectl wait --for=condition=Ready ingress/sdd-app-ingress -n sdd-apps --timeout=300s && curl -f -s -o /dev/null -w "%{http_code}" http://$(kubectl get ingress sdd-app-ingress -n sdd-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/health | grep -q '200'`)

## 3. Assumptions & Technical Constraints
- **Script Language**: Bash scripts with POSIX compliance
- **Dependencies**: AWS CLI v2, kubectl v1.28, Helm v3.12
- **IAM / Security Boundaries**: Scripts inherit permissions from execution environment
- **Storage / Backup Boundaries**: Manual backup procedures, automated monitoring
- **Testing Policy**: No unit or E2E test generation - validation performed directly against AWS infrastructure using CLI tools
- **Provider Versions**: AWS CLI >= 2.0, kubectl >= 1.28.0, Helm >= 3.12.0