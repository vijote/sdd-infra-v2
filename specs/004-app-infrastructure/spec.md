# Spec: Application Infrastructure (EBS CSI + Ingress + Namespaces)

**Feature Branch**: `004-app-infrastructure` | **Date**: 2026-09-09 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: EBS CSI Driver / EBS node-role IAM / ebs-gp3 StorageClass / Load Balancer (ingress)
- **Kubernetes / Cluster Scope**: Namespaces / EBS CSI (`ebs.csi.aws.com`) / NGINX Ingress Controller / StorageClass
- **Target Services / Modules**: EBS CSI driver (`release-1.65`), NGINX Ingress (`controller-v1.15.1`), `sdd-apps` namespace
- **Security & CI/CD**: node-role IAM for EBS (no IRSA — kubeadm has no OIDC provider); all `kubectl` applies via SSM Run Command on the control plane

> **Scope note**: cert-manager + Let's Encrypt TLS is **out of scope** here — deferred to `004-1-cert-manager`.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# EBS node-role IAM — added to the cluster-plumbing module (003-1 node role).
# The EBS CSI controller (Deployment) + node plugin (DaemonSet) run as pods on nodes and
# use the node's instance-profile credentials via IMDS (no IRSA on kubeadm).
resource "aws_iam_role_policy" "node_ebs_csi" {
  name = "sdd-k8s-platform-node-ebs-csi"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "ec2:CreateVolume", "ec2:DeleteVolume", "ec2:AttachVolume", "ec2:DetachVolume",
        "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeVolumes", "ec2:DescribeTags",
        "ec2:DescribeInstances", "ec2:DescribeSnapshots", "ec2:ModifyVolume"
      ]
      Resource = "*"
    }]
  })
}

# kubectl applies — version-controlled null_resource in the dev env (Flannel pattern, 003-3/003-11).
# Runs on the CI runner; issues `aws ssm send-command` to the control plane. The actual
# `kubectl apply` runs there with KUBECONFIG=/etc/kubernetes/admin.conf. Idempotent (kubectl apply).
resource "null_resource" "apply_app_infrastructure" {
  depends_on = [module.worker_nodes]
  triggers = {
    ebs_csi_ref = "release-1.65"
    ingress_ref = "controller-v1.15.1"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # SSM-agent wait + bootstrap-instance-id gate (identical to 003-11 Flannel gate).
      # On a persistent 003 cluster the instance-id param already matches -> returns immediately.
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        [ "$${SSM_ID}" = "$${INSTANCE_ID}" ] && break; sleep 10
      done
      for i in $(seq 1 60); do
        BOOTSTRAP_ID=$(aws ssm get-parameter --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
          --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
        [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ] && break; sleep 10
      done
      [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ] || { echo "bootstrap gate timeout" >&2; exit 1; }
      CMD_ID=$(aws ssm send-command --instance-ids "$${INSTANCE_ID}" \
        --document-name AWS-RunShellScript \
        --parameters "commands=[
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl create namespace sdd-apps --dry-run=client -o yaml | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\",
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -k 'github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.65'\",
          \"echo '<EBS_GP3_STORAGECLASS_BASE64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\",
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml\"
        ]" --timeout-seconds 600 --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation --instance-id "$${INSTANCE_ID}" --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        [ "$${STATUS}" = "Success" ] && exit 0
        { [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; } && { echo "apply failed: $${STATUS}" >&2; exit 1; }
        sleep 10
      done
      echo "apply timed out" >&2; exit 1
    EOT
  }
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts

- **Namespace** `sdd-apps` — application workloads (005) land here.
- **EBS CSI driver** — `kubectl apply -k` gitops overlay `release-1.65` (creates `ebs-csi-controller` Deployment + `ebs-csi-node` DaemonSet in `kube-system`, provisioner `ebs.csi.aws.com`).
- **ebs-gp3 StorageClass** (base64-encoded into the SSM command to avoid JSON-escaping, per 003-6):
```yaml
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
```
- **NGINX Ingress** — static cloud manifest `controller-v1.15.1` (creates `ingress-nginx` namespace, `ingress-nginx-controller` Deployment, `LoadBalancer` Service, `IngressClass` `nginx` default).

### 1.3 Data & Storage Contracts
- **EBS CSI Driver**: gp3 volumes, 3000 IOPS, 125 MB/s, ext4.
- **StorageClass**: `ebs-gp3`, `Retain` policy, `WaitForFirstConsumer` binding, `allowVolumeExpansion: true`.
- **Persistent Volumes**: dynamic provisioning via `ebs.csi.aws.com` (consumed by 005 MySQL StatefulSet PVC).

### 1.4 Network & Security Contracts
- **Ingress Load Balancer**: internet-facing `LoadBalancer` Service created by the nginx-ingress static cloud manifest (default AWS LB).
- **EBS node-role IAM**: `sdd-k8s-platform-node-role` gains EBS volume lifecycle actions (controller + node plugin use node instance-profile creds via IMDS).
- **No IRSA**: kubeadm cluster has no OIDC provider; pod AWS access is via the node instance profile.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-008 execute **on the control plane via SSM** (`aws ssm send-command` + poll `aws ssm get-command-invocation` until `Status` = `Success`) — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-008 are **user-managed verification** (defined here, not added to `terraform-apply.yml`).

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: EBS CSI controller + node plugin ready
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=ebs-csi-controller -n kube-system --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=ebs-csi-node -n kube-system --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: ebs-gp3 StorageClass present with EBS provisioner
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get storageclass ebs-gp3 -o jsonpath={.provisioner}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q 'ebs.csi.aws.com'
  ```
- [ ] AC-005: NGINX Ingress controller rolled out
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-006: Ingress Load Balancer has an external hostname
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath={.status.loadBalancer.ingress[0].hostname}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -qE '\.elb\.'
  ```
- [ ] AC-007: sdd-apps namespace exists
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get namespace sdd-apps -o jsonpath={.metadata.name}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '^sdd-apps$'
  ```
- [ ] AC-008: EBS node-role policy attached (Terraform-managed, verified in plan/apply)
  ```bash
  terraform state list | grep -q 'aws_iam_role_policy.node_ebs_csi'
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `003-1-cluster-plumbing` (node role `sdd-k8s-platform-node-role`) + `003-2-control-plane` (control plane instance ID, bootstrap-instance-id param) + `003-3-worker-nodes` (Ready 3-node cluster, Flannel CNI).
- **Downstream Consumer**: `005-app-deployment` (MySQL StatefulSet + PVC on `ebs-gp3`, Node.js backend, SPA) consumes the `sdd-apps` namespace, EBS CSI, and ingress.
- **No IRSA**: kubeadm has no OIDC provider; EBS CSI controller + node plugin use the node instance-profile credentials via IMDS.
- **Idempotency**: all `kubectl apply` operations are re-runnable; the `null_resource` re-triggers only on a pinned-version change.
- **Testing Policy**: No unit or E2E test generation — validation performed via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
