# Spec: CCM Instance Cluster Tag

**Feature Branch**: `004-6-ccm-instance-cluster-tag` | **Date**: 2026-09-13 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources, no IAM, no new manifest)
- **Kubernetes / Cluster Scope**: `aws-cloud-controller-manager` (`kube-system`) — unblocks ClusterID init
- **Target Services / Modules**: `terraform/modules/control-plane/main.tf` + `terraform/modules/worker-nodes/main.tf` (instance `tags`)
- **Root Cause (confirmed via 004-5 `--v=4` trace)**: The CCM's `ClusterID()` init path calls `DescribeInstances` for its own instance (from IMDS) and reads the `kubernetes.io/cluster/<name>` tag from the **instance's tags** (returned in the `DescribeInstances` response) — **not** from the VPC. The 004-5 trace shows:
  ```
  ec2 DescribeInstances (i-0efe35678d39e688c) → 200 OK
  ec2 DescribeInstances (i-0efe35678d39e688c) → 200 OK
  tags.go:95] Tag "KubernetesCluster" nor "kubernetes.io/cluster/..." not found
  main.go:112] Cloud provider could not be initialized
  ```
  **No `DescribeSubnets` or `DescribeVpcs` calls** — the CCM never resolves the VPC. It reads the tag from the instance, which does **not** have the `kubernetes.io/cluster/sdd-k8s-platform` tag (only the **VPC** does, added in 004-4). Hence "tag not found" → fatal.

## 2. Infrastructure Contracts

### 2.1 Control Plane Instance (Modify — `modules/control-plane/main.tf`)
- **Target**: `aws_instance.control_plane` `tags` block (line ~35)
- **Change**: add `kubernetes.io/cluster/sdd-k8s-platform = "owned"` to the `tags` map:
  ```hcl
  tags = merge(var.tags, {
    Name                                = "sdd-k8s-control-plane"
    "kubernetes.io/cluster/sdd-k8s-platform" = "owned"
  })
  ```

### 2.2 Worker Instances (Modify — `modules/worker-nodes/main.tf`)
- **Target**: `aws_instance.worker` `tags` block (line ~47)
- **Change**: add `kubernetes.io/cluster/sdd-k8s-platform = "owned"` to the `tags` map:
  ```hcl
  tags = merge(var.tags, {
    Name                                = "sdd-k8s-${each.key}"
    "kubernetes.io/cluster/sdd-k8s-platform" = "owned"
  })
  ```

### 2.3 No Other Changes
- No new `null_resource`, no IAM, no manifest, no CCM arg change, no VPC tag change (the VPC tag from 004-4 stays — it's harmless and may be used by other tooling).
- The CCM `--v=4` flag from 004-5 **stays** (useful for future diagnostics; no harm).

## 3. Acceptance Criteria

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows only the instance tag changes
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2; plan shows tag updates on `aws_instance.control_plane` + `aws_instance.worker` (2 instances), zero other changes

- [ ] AC-003: Control plane instance has the cluster tag
  ```
  aws ec2 describe-instances --instance-ids <CP_ID> \
    --query 'Reservations[0].Instances[0].Tags[?Key==`kubernetes.io/cluster/sdd-k8s-platform`].Value' \
    --output text
  ```
  **Expected**: `owned`

- [ ] AC-004: Worker instances have the cluster tag
  ```
  aws ec2 describe-instances --filters "Name=tag-key,Values=kubernetes.io/cluster/sdd-k8s-platform" \
    --query 'Reservations[].Instances[].InstanceId' --output text
  ```
  **Expected**: both worker instance IDs listed

- [ ] AC-005: CCM pod is `1/1 Running` (no crash-loop)
  ```
  kubectl get pods -n kube-system -l app=aws-cloud-controller-manager
  ```
  **Expected**: 1 pod `1/1 Running`, 0 restarts

- [ ] AC-006: CCM rollout complete
  ```
  kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s
  ```
  **Expected**: `deployment "aws-cloud-controller-manager" successfully rolled out`

- [ ] AC-007: Ingress Service EXTERNAL-IP populated (ELB created)
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller
  ```
  **Expected**: EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`)

- [ ] AC-008: Ingress ADDRESS populated
  ```
  kubectl get ingress -n sdd-apps app-ingress
  ```
  **Expected**: ADDRESS = ELB DNS name (not empty)

## 4. Out of Scope
- No VPC tag change (004-4's VPC tag stays — harmless)
- No CCM version change (stays on `v1.28.11-eks-1-28-64`)
- No CCM arg change (`--v=4` from 004-5 stays)
- No Route53 / TLS (deferred)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — AC-003/004/005 (EXTERNAL-IP, Ingress ADDRESS, public-subnet annotation) become verifiable once the CCM is Ready
- **008 (ECR + real apps)** — Ingress path routing (`/api` → backend) is live on the ELB
