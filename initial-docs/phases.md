# Project Regeneration Phases

## Minimal Regeneration Plan (Single Environment)

### **Phase 1: Foundation Layer**
- **VPC Networking** (`src/terraform/modules/networking/`)
  - VPC (10.0.0.0/16)
  - 1 public subnet (10.0.1.0/24) 
  - 2 private subnets (10.0.2.0/24, 10.0.3.0/24)
  - Internet Gateway + Route Tables
  - Security Groups (control plane, workers, ingress)

### **Phase 2: State Management**
- **Terraform Backend** (`src/terraform/modules/state/`)
  - S3 bucket data source for remote state
  - Manual bucket provisioning

### **Phase 3: Compute Layer**
- **Kubernetes Cluster** (`src/terraform/modules/kubernetes/`)
  - 3-node kubeadm cluster on EC2
  - 1 control plane (t2.medium) + 2 workers (t2.small)
  - Ubuntu 22.04 AMI with cloud-init bootstrap
  - SSH key generation and IAM roles

### **Phase 4: CI/CD Foundation**
- **GitHub Actions** (`.github/workflows/`)
  - OIDC authentication setup
  - Terraform plan/apply workflows
  - Single environment deployment
- **IAM Roles** (`src/aws_iam/`)
  - CloudFormation for OIDC provider
  - Bootstrap role → Terraform execution role

### **Phase 5: Application Infrastructure**
- **K8s Infrastructure** (`src/terraform/modules/application-infrastructure/`)
  - Namespace creation
  - Storage configuration
  - Ingress controller setup
  - Cluster bootstrap utilities

### **Phase 6: Application Deployment**
- **Workloads** (`src/terraform/modules/application-deployment/`)
  - MySQL StatefulSet with PVC
  - Application deployments
  - Kubernetes secrets and services

### **Phase 7: Main Configuration**
- **Single Environment** (`src/terraform/main.tf`)
  - Module composition (networking → kubernetes → application-infrastructure → application-deployment)
  - Provider configurations
  - Variable definitions

### **Phase 8: Operational Tooling**
- **Scripts** (`scripts/`)
  - Deployment automation
  - Validation and health checks
  - Monitoring utilities

This simplifies the architecture to a single, production-ready environment with all the essential components for a self-managed Kubernetes platform on AWS.