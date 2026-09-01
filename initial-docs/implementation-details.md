# Critical Implementation Details & Hard-Won Lessons

## Kubernetes Bootstrap Process

### **Control Plane Cloud-Init Essentials**
```yaml
# Critical: Use specific Kubernetes version (v1.28) - don't use latest!
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key

# Critical: SystemdCgroup must be true for containerd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Critical: Include both public and private IPs in TLS cert
kubeadm init \
  --apiserver-advertise-address=$PRIVATE_IP \
  --apiserver-cert-extra-sans=$PUBLIC_IP,$PRIVATE_IP,127.0.0.1,localhost \
  --ignore-preflight-errors=NumCPU,Mem  # t3.micro fails CPU check
```

### **Worker Node Bootstrap Pattern**
```yaml
# Critical: Workers must poll SSM for join command
until JOIN_CMD=$(aws ssm get-parameter --name "/k8s/kubeadm/join-command" --with-decryption --query "Parameter.Value" --output text --region $REGION 2>/dev/null); do
  echo "Control Plane aún no ha publicado el token. Reintentando en 10 segundos..."
  sleep 10
done
eval "$JOIN_CMD"
```

## IAM Permission Patterns

### **EC2 Instance Role (Properly Scoped)**
```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:PutParameter",
    "ssm:GetParameter", 
    "ssm:GetParameters",
    "ssm:AddTagsToResource"
  ],
  "Resource": "arn:aws:ssm:*:*:parameter/k8s/kubeadm/join-command"
}
```

### **GitHub Actions Role (Administrative for Simplicity)**
```json
{
  "Effect": "Allow",
  "Action": ["ec2:*", "iam:*", "ssm:*"],
  "Resource": "*"
}
```

## Terraform State Management

### **Manual S3 Bucket Pattern**
```hcl
# Don't manage the state bucket with Terraform - circular dependency!
data "aws_s3_bucket" "terraform_state" {
  bucket = var.aws_state_bucket_name
}
```

### **Backend Configuration**
```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"  # Optional but recommended
  }
}
```

## Kubernetes Application Deployment

### **Provider Configuration Pattern**
```hcl
provider "kubernetes" {
  config_path = "~/.kube/config"
  insecure = true  # Required for self-signed certs
  
  host                   = var.cluster_endpoint
  cluster_ca_certificate = var.cluster_ca_certificate
  token                  = var.cluster_token
}
```

### **MySQL StatefulSet Critical Settings**
```yaml
# Must use base64 encoding for secrets
data:
  root-password: base64encode(var.mysql_root_password)
  
# PVC requires storage class - EBS CSI driver must be installed
storageClassName: "gp2"
```

## Validation Patterns

### **Pod Health Checking**
```bash
# Wait for pods with timeout
kubectl wait --for=condition=ready pod \
    -l app=${app_name} \
    -n ${namespace} \
    --timeout=${TIMEOUT}s

# Check both status and readiness
pod_status=$(kubectl get pods -l app=${app_name} -n ${namespace} -o jsonpath='{.items[*].status.phase}')
ready_count=$(kubectl get pods -l app=${app_name} -n ${namespace} -o jsonpath='{.items[*].status.containerStatuses[*].ready}')
```

## Common Pitfalls & Solutions

### **1. Instance Size Issues**
- **Problem**: t3.micro fails kubeadm preflight checks (CPU/Memory)
- **Solution**: Use t2.small for workers and t2.medium for control-plane (cost tradeoff accepted)
- **Alternative**: If using smaller instances, add `--ignore-preflight-errors=NumCPU,Mem`

### **2. Containerd Configuration**
- **Problem**: Default containerd config doesn't work with Kubernetes
- **Solution**: `SystemdCgroup = true` is mandatory

### **3. TLS Certificate Issues**
- **Problem**: Workers can't connect to control plane from external access
- **Solution**: Include all IPs in `--apiserver-cert-extra-sans`

### **4. SSM Parameter Timing**
- **Problem**: Workers start before control plane publishes join command
- **Solution**: Polling loop with sleep/retry pattern

### **5. EBS CSI Driver**
- **Problem**: MySQL PVC can't get storage
- **Solution**: Attach `AmazonEBSCSIDriverPolicy` to node role

### **6. Kubernetes Provider Authentication**
- **Problem**: Can't connect to cluster from Terraform
- **Solution**: Use `insecure = true` for self-signed certs

## GitHub Actions Workflow Patterns

### **OIDC Authentication**
```yaml
permissions:
  id-token: write    # Required for OIDC
  contents: read     # Required for checkout

env:
  AWS_BOOTSTRAP_ROLE: ${{ vars.AWS_BOOTSTRAP_ROLE }}
  AWS_TERRAFORM_ROLE: ${{ vars.AWS_TERRAFORM_ROLE }}
```

### **Multi-Phase Deployment**
```yaml
jobs:
  # Phase 1: Base infrastructure (VPC, EC2)
  apply-base-infra:
    # terraform apply -target=module.networking
    # terraform apply -target=module.kubernetes
  
  # Phase 2: Applications (depends on cluster)
  apply-apps:
    needs: apply-base-infra
    # terraform apply -target=module.application-infrastructure
    # terraform apply -target=module.application-deployment
```

## Operational Scripts Patterns

### **Health Check Structure**
```bash
# 1. Check cluster connectivity
kubectl cluster-info

# 2. Check node status
kubectl get nodes -o wide

# 3. Check pod health by namespace
kubectl get pods -n demo-apps

# 4. Check services and endpoints
kubectl get svc -n demo-apps
```

### **Rollback Pattern**
```bash
# Get previous deployment
kubectl rollout history deployment/${app_name} -n ${namespace}

# Rollback to previous revision
kubectl rollout undo deployment/${app_name} -n ${namespace}
```

## Version Pinning (Critical!)

### **Kubernetes Components**
```bash
# Always pin to specific version, don't use latest!
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key
apt-mark hold kubelet kubeadm kubectl  # Prevent auto-upgrades
```

### **Terraform Providers**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Pin major version
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}
```

## Security Considerations

### **Secret Management**
- Use GitHub Secrets for sensitive values
- Base64 encode Kubernetes secrets
- Never commit passwords to repo

### **Network Security**
- Security groups should be least privilege
- Use private subnets for worker nodes
- Only expose necessary ports via security groups

## Debugging Tips

### **Cloud-Init Debugging**
```bash
# Check cloud-init logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Check specific services
sudo systemctl status containerd
sudo systemctl status kubelet
```

### **Kubernetes Debugging**
```bash
# Check cluster status
kubectl get componentstatuses

# Check node conditions
kubectl describe nodes

# Check pod events
kubectl describe pod <pod-name> -n <namespace>
```

This implementation details document captures the critical technical decisions and patterns that emerged from building this project. Use it as a reference to avoid common pitfalls and implement the same robust patterns.