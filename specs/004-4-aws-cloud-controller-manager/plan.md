# Architecture Delta: AWS Cloud Controller Manager (CCM)

**Branch**: `004-4-aws-cloud-controller-manager` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/manifests/aws-ccm.yaml` | Create | CCM ServiceAccount + ClusterRole + ClusterRoleBinding + Deployment (`kube-system`, 1 replica, `v1.28.x` image, args `--cloud-provider=aws --configure-cloud-routes=false --cluster-name=sdd-k8s-platform`) |
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Add inline policy `node_aws_ccm` to `sdd-k8s-platform-node-role` (ELB lifecycle + EC2 describe/tag, `Resource=*`) — mirrors `node_ebs_csi` |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_aws_ccm`: `depends_on = [apply_app_frontend_ingress]`, trigger `ccm_version`, local-exec SSM command that (1) applies `aws-ccm.yaml`, (2) annotates `ingress-nginx-controller` Service with public subnet IDs, (3) waits for CCM rollout |

## 2. Key Design Decisions

### 2.1 Local manifest (not the official static manifest)
We author a **local** `aws-ccm.yaml` (matching the 005/006/007 pattern) rather than applying the official cloud-provider-aws static manifest, so we control the args (`--cluster-name`, `--configure-cloud-routes`) and the RBAC to fit a kubeadm cluster. The CCM uses:
- **K8s API**: in-cluster ServiceAccount (`aws-cloud-controller-manager`) — no kubeconfig file needed (runs as a pod with a SA)
- **AWS API**: node instance profile via IMDS (no IRSA — kubeadm has no OIDC provider), same as EBS CSI

### 2.2 CCM args
- `--cloud-provider=aws` — enable the AWS provider
- `--configure-cloud-routes=false` — **critical**: Flannel uses VXLAN (pod CIDR `192.168.0.0/16`), not VPC routes. Prevents the CCM from managing/conflicting with node routes.
- `--cluster-name=sdd-k8s-platform` — tags the ELB + resources with `kubernetes.io/cluster/sdd-k8s-platform` (matches cluster identity)

### 2.3 Image
`602401143452.dkr.ecr.us-west-2.amazonaws.com/aml/boilerplate/cloud-controller-manager:aws-1.28.0` — the official boilerplate CCM image for v1.28.0 (matches cluster K8s 1.28.0 minor). Pulled via NAT egress, no `imagePullSecrets`.

### 2.4 Internet-facing ELB (the annotation)
All 3 nodes are in **private** subnets. The CCM defaults to creating the ELB in the node subnets → **internal** LB. To force an **internet-facing** ELB, the SSM command annotates the `ingress-nginx-controller` Service:
```
service.beta.kubernetes.io/aws-load-balancer-subnets = <public subnet IDs, comma-separated>
```
Public subnet IDs come from `module.vpc.public_subnet_ids` (existing output), injected via `%%TOKEN%%` replace (007 pattern).

### 2.5 IAM (node role)
New inline policy `node_aws_ccm` on `sdd-k8s-platform-node-role` (mirrors `node_ebs_csi`, `Resource=*`, dev-only). Actions:
- `ec2`: `AssociateRouteTable`, `CreateTags`, `CreateVolume`, `CreateNetworkInterface`, `DeleteNetworkInterface`, `DeleteSecurityGroup`, `DeleteVolume`, `DeregisterInstancesFromLoadBalancer`, `Describe*`, `DetachVolume`, `ModifyInstanceAttribute`, `RegisterInstancesWithLoadBalancer`
- `elasticloadbalancing`: `AddTags`, `CreateListener`, `CreateLoadBalancer`, `CreateTargetGroup`, `DeleteListener`, `DeleteLoadBalancer`, `DeleteTargetGroup`, `DescribeListeners`, `DescribeLoadBalancers`, `DescribeTags`, `DescribeTargetGroups`, `ModifyLoadBalancerAttributes`, `ModifyTargetGroup`, `RegisterTargets`, `RemoveTags`, `SetSecurityGroups`, `SetSubnets`
- `autoscaling`: `DescribeAutoScalingGroups`

## 3. SSM Command Flow (local-exec)
Single `&&`-chained command on the control plane (gated on `kubeadm-bootstrap-instance-id` SSM param, per 003 pattern):
1. `echo '<base64 aws-ccm.yaml>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -`
2. `KUBECONFIG=... kubectl annotate svc ingress-nginx-controller -n ingress-nginx service.beta.kubernetes.io/aws-load-balancer-subnets='<%%PUBLIC_SUBNETS%%>' --overwrite`
3. `KUBECONFIG=... kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s`

## 4. Risks / Notes
- **Image tag**: if `aws-1.28.0` is wrong, the pod is `ImagePullBackOff` (obvious, one-line fix).
- **ELB creation latency**: the CCM creates the ELB asynchronously after rollout; EXTERNAL-IP may take 1-2 min to appear (AC-003/004 account for this).
- **No Terraform AWS resources**: the ELB is created by the CCM at runtime, not Terraform — so `terraform plan` shows only the IAM policy + null_resource (no ELB in state).
- **Route53 deferred**: the ELB DNS name is the target; a follow-on spec adds the A record.
