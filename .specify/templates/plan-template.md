# Architecture Delta: [FEATURE_NAME]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [specs/###-feature-name/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/[module]/main.tf` | Create/Modify | Core AWS resource declarations |
| `terraform/modules/[module]/variables.tf` | Create/Modify | Input variables and validation rules |
| `terraform/modules/[module]/outputs.tf` | Create/Modify | Exported outputs for downstream modules |
| `terraform/environments/[env]/main.tf` | Modify | Root module instantiation & remote state |
| `k8s/bootstrap/[script].sh` | Create/Modify | Kubeadm initialization and join automation |
| `k8s/addons/cni/flannel.yaml` | Create | Flannel CNI manifest with VXLAN backend |
| `k8s/addons/cert-manager/values.yaml` | Create/Modify | Helm values for cert-manager |
| `k8s/addons/ingress-nginx/values.yaml` | Create | NGINX Ingress Controller configuration |
| `k8s/addons/storage/ebs-csi.yaml` | Create | AWS EBS CSI driver and StorageClass |
| `k8s/manifests/[workload]/` | Create/Modify | Kubernetes manifests (MySQL StatefulSet, PVC, Services) |

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: [VPC, Subnets, IAM Instance Profiles, Security Groups, EC2 Compute]
- **Cluster Control Plane & Core Addons**: [kubeadm init/join, Flannel CNI Plugin, AWS EBS CSI Driver, StorageClass]
- **Platform Services**: [cert-manager ClusterIssuer, NGINX Ingress Controller, CoreDNS, Cluster Autoscaler]
- **Application Workloads**: [MySQL StatefulSet/Helm release, application deployments]
- **Shared Dependencies**: [AWS provider version constraints, Kubernetes minor version, Helm repository versions]

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: Apply network, IAM, compute, and security groups infrastructure.
2. **Stage 2 - Kubeadm Bootstrap**: Execute control-plane initialization, token generation, and worker node joining.
3. **Stage 3 - Core Addons**: Deploy Flannel CNI (VXLAN) and AWS EBS CSI storage driver.
4. **Stage 4 - Platform Services**: Deploy cert-manager, NGINX Ingress Controller, CoreDNS, and Cluster Autoscaler.
5. **Stage 5 - Workloads**: Provision MySQL StatefulSet/Helm with persistent volume claims and credentials.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode`
- **Manifest Validation**: `helm lint [chart-path] && kubectl apply --dry-run=client -f [manifest].yaml`
- **Infrastructure Health**: `kubectl wait --for=condition=Ready nodes --all --timeout=300s`
- **Service Rollout**: `kubectl rollout status deployment/[deployment-name] --timeout=600s`
- **Endpoint Verification**: `curl -f -s [https-endpoint]/health || exit 1`
- **Resource Verification**: `kubectl get pods -n [namespace] -l app=[app-label] --field-selector=status.phase=Running`
