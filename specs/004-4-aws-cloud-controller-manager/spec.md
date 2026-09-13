# Spec: AWS Cloud Controller Manager (CCM)

**Feature Branch**: `004-4-aws-cloud-controller-manager` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: AWS Cloud Controller Manager (CCM) v1.28.x / node-role IAM (ELB + EC2) / ingress-nginx Service annotation (public subnets)
- **Kubernetes / Cluster Scope**: CCM Deployment (`kube-system`) / `ingress-nginx-controller` LoadBalancer Service (EXTERNAL-IP) / Ingress ADDRESS
- **Target Services / Modules**: AWS CCM (`v1.28.x`, matching cluster K8s 1.28.0), `sdd-k8s-platform-node-role` IAM, `ingress-nginx` Service
- **Root Cause**: The `ingress-nginx-controller` LoadBalancer Service has been `<pending>` since 004 — on AWS, a `LoadBalancer` Service only gets an ELB when the **cloud-controller-manager** runs, and kubeadm does not install the CCM by default. No CCM pod exists in `kube-system` (verified: `kubectl get pods -n kube-system | grep -i cloud` → empty). Additionally, all 3 nodes are in **private** subnets (CP `private[0]`, workers `private[1]`/`[2]`), so the CCM would default to an **internal** ELB; an annotation is required to force the ELB into the **public** subnets (internet-facing).

## 2. Infrastructure Contracts

### 2.1 AWS CCM Deployment (new manifest)
- **File**: `terraform/environments/dev/manifests/aws-ccm.yaml` (Create)
- **Objects**: ServiceAccount `aws-cloud-controller-manager` + ClusterRole + ClusterRoleBinding + Deployment `aws-cloud-controller-manager` in `kube-system`
- **Image**: AWS CCM `v1.28.x` (matches cluster K8s 1.28.0 minor) — pulled via NAT egress, no `imagePullSecrets`
- **Args**: `--cloud-provider=aws`, `--configure-cloud-routes=false` (Flannel uses VXLAN, not cloud routes — prevents CCM route conflicts), `--cluster-name=sdd-k8s-platform`
- **Replicas**: 1 (leader-elected; single instance for dev)

### 2.2 Node Role IAM (Modify — `cluster-plumbing/main.tf`)
- **New inline policy** `node_aws_ccm` on `sdd-k8s-platform-node-role` (mirrors the `node_ebs_csi` pattern — CCM uses the node instance profile via IMDS, no IRSA on kubeadm)
- **Actions** (per official AWS CCM IAM policy, `Resource = "*"` — dev-only, matches `node_ebs_csi` scope):
  - `ec2`: `AssociateRouteTable`, `CreateTags`, `CreateVolume`, `CreateNetworkInterface`, `DeleteNetworkInterface`, `DeleteSecurityGroup`, `DeleteVolume`, `DeregisterInstancesFromLoadBalancer`, `Describe*`, `DetachVolume`, `ModifyInstanceAttribute`, `RegisterInstancesWithLoadBalancer`
  - `elasticloadbalancing`: `AddTags`, `CreateListener`, `CreateLoadBalancer`, `CreateTargetGroup`, `DeleteListener`, `DeleteLoadBalancer`, `DeleteTargetGroup`, `DescribeListeners`, `DescribeLoadBalancers`, `DescribeTags`, `DescribeTargetGroups`, `ModifyLoadBalancerAttributes`, `ModifyTargetGroup`, `RegisterTargets`, `RemoveTags`, `SetSecurityGroups`, `SetSubnets`
  - `autoscaling`: `DescribeAutoScalingGroups`

### 2.3 Ingress Service Annotation (Modify — same SSM command)
- **Target**: `ingress-nginx-controller` Service in `ingress-nginx`
- **Annotation**: `service.beta.kubernetes.io/aws-load-balancer-subnets` = the **public** subnet IDs (comma-separated), injected via `%%TOKEN%%` replace (007 pattern) — forces the ELB into public subnets → **internet-facing**
- **Why**: nodes are in private subnets; without this, the CCM creates an internal ELB

### 2.4 Terraform Apply (Modify — `dev/main.tf`)
- **New resource**: `null_resource.apply_aws_ccm` (mirrors `apply_app_backend` pattern)
- **depends_on**: `[null_resource.apply_app_frontend_ingress]` (CCM runs after all app workloads + the ingress Service exist)
- **triggers**: `ccm_version = "v1.28.x"`
- **local-exec**: SSM Run Command on control plane — (1) apply `aws-ccm.yaml` manifest, (2) annotate the `ingress-nginx-controller` Service with the public subnet IDs, (3) wait for CCM rollout
- **Public subnet IDs**: read from `module.vpc.public_subnet_ids` (already an output)

## 3. Acceptance Criteria

- [ ] AC-001: CCM Deployment rolled out
  ```
  kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s
  ```
  **Expected**: `deployment "aws-cloud-controller-manager" successfully rolled out`

- [ ] AC-002: CCM pod Running
  ```
  kubectl get pods -n kube-system -l app=aws-cloud-controller-manager
  ```
  **Expected**: 1 pod `1/1 Running`, 0 restarts

- [ ] AC-003: ingress-nginx-controller Service has EXTERNAL-IP
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller
  ```
  **Expected**: `EXTERNAL-IP` = an ELB DNS name (e.g. `a1b2c3-....elb.us-east-1.amazonaws.com`), NOT `<pending>`

- [ ] AC-004: Ingress ADDRESS populated
  ```
  kubectl get ingress -n sdd-apps app-ingress
  ```
  **Expected**: `ADDRESS` = the same ELB DNS name

- [ ] AC-005: ELB is internet-facing (public subnets)
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-subnets}'
  ```
  **Expected**: the public subnet IDs (matching `module.vpc.public_subnet_ids`)

## 4. Out of Scope
- No new Terraform AWS resources (CCM is a K8s Deployment; the ELB is created by the CCM at runtime, not Terraform)
- No Route53 record (deferred — the ELB DNS name is the target; a follow-on spec adds the Route53 A record)
- No TLS/HTTPS cert (the ELB exposes 80/443; 443 uses the ingress-nginx fake cert until cert-manager + a real cert)
- No changes to CCM target-registration logic (standard classic ELB behavior)

## 5. Downstream Consumer
- **007-app-frontend-ingress** (already deployed) — the Ingress ADDRESS becomes populated, enabling external access
- **Route53 follow-on spec** — the ELB DNS name is the target for the A record
- **008 (ECR + real apps)** — the real apps will be reachable via the same ELB
