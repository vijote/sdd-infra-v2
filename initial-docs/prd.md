# Product Requirements Document (PRD)
## Self-Managed Kubernetes Platform on AWS

### Project Overview
This project delivers a complete, self-managed Kubernetes platform built from scratch on AWS infrastructure. The platform is designed for learning, cost optimization, and full control over the infrastructure stack, avoiding managed services like EKS to provide deeper understanding of Kubernetes internals.

### Core Objectives
1. **Educational Platform**: Build a complete Kubernetes platform from first principles to understand every component
2. **Cost Optimization**: Use smaller instance sizes and avoid managed service fees
3. **Security First**: Implement least-privilege access patterns with no static credentials
4. **Automation First**: Full CI/CD pipeline with infrastructure as code

### Technical Scope

#### Infrastructure Components
- **VPC Foundation**: Custom VPC with public/private subnet architecture
- **Compute Layer**: 3-node kubeadm cluster (1 control plane, 2 workers)
- **Networking**: Flannel CNI for pod networking, security groups for isolation
- **Storage**: In-cluster database with persistent volumes
- **State Management**: Remote Terraform state with S3 backend

#### Application Stack
- **Frontend**: Single Page Application (SPA)
- **Backend**: Node.js microservice API
- **Database**: MySQL deployed as Kubernetes StatefulSet
- **Ingress**: External access management for applications

#### CI/CD Pipeline
- **Authentication**: GitHub Actions OIDC integration (no static AWS credentials)
- **Deployment**: Automated infrastructure and application deployment
- **Environment**: Single environment (dev) with production-ready configurations
- **Validation**: Automated health checks and deployment verification

### Key Design Decisions

#### Self-Managed vs Managed Services
- **kubeadm on EC2** instead of EKS: Deeper learning experience and cost control
- **In-cluster database** instead of RDS: Understanding of stateful workloads
- **Manual IAM provisioning**: Avoid circular dependencies in bootstrap process

#### Security Architecture
- **OIDC Authentication**: Temporary credentials per workflow run
- **Principle of Least Privilege**: Applied selectively
  - **EC2 Instances**: Properly scoped permissions (SSM parameters, EBS CSI only)
  - **GitHub Actions**: Uses administrative permissions for simplicity (ec2:*, iam:*, ssm:*)
- **No Secrets in Code**: All sensitive data via environment variables/secrets

#### Operational Excellence
- **Infrastructure as Code**: All resources defined in Terraform modules
- **Modular Design**: Clear separation between infrastructure layers
- **Automation**: Comprehensive scripts for deployment and validation

### Success Criteria
1. **Functional**: Complete platform running real applications
2. **Secure**: No static credentials, proper IAM boundaries
3. **Automated**: Zero-touch deployment from git push to running applications
4. **Observable**: Health checks, monitoring, and validation tools
5. **Documented**: Clear understanding of each component and its purpose

### Out of Scope
- Multi-environment management (only dev environment)
- Advanced Kubernetes features (service mesh, advanced scheduling)
- Managed database services (RDS, DocumentDB)
- Container registry management (assumes external ECR)
- Advanced monitoring (Prometheus, Grafana stacks)

### Intended Use Cases
- **Learning**: Understanding Kubernetes internals and AWS infrastructure
- **Development**: Complete development environment for cloud-native applications
- **Cost Optimization**: Minimal infrastructure costs for personal projects
- **Reference Architecture**: Template for similar self-managed platforms

### Technical Constraints
- **Region**: us-east-1 (can be parameterized)
- **Instance Types**: t2.medium (control plane), t2.small (workers)
- **Kubernetes Version**: Latest stable via kubeadm
- **Terraform Version**: >= 1.0
- **Provider**: AWS only (no multi-cloud)

### Project Kickoff Prompt
Use this PRD to understand the full scope and intentions of the project. The goal is to build a complete, production-ready Kubernetes platform from scratch while maintaining simplicity and focusing on learning. Each phase should build incrementally on the previous one, with clear validation at each step.