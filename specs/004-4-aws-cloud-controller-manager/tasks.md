# Execution Graph (DAG): AWS Cloud Controller Manager (CCM)

**Input**: Design documents from `/specs/004-4-aws-cloud-controller-manager/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 3 implementation tasks + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Create `terraform/environments/dev/manifests/aws-ccm.yaml`: ServiceAccount `aws-cloud-controller-manager` + ClusterRole (nodes, nodes/proxy, services, services/status, events, endpoints, persistentvolumes, pv protection, configmaps, secrets, leases) + ClusterRoleBinding + Deployment `aws-cloud-controller-manager` in `kube-system` (1 replica, image `602401143452.dkr.ecr.us-west-2.amazonaws.com/aml/boilerplate/cloud-controller-manager:aws-1.28.0`, args `--cloud-provider=aws --configure-cloud-routes=false --cluster-name=sdd-k8s-platform`, serviceAccountName, livenessProbe /healthz:10258)
- [x] T002 [Stage 1: Bootstrap] Add inline policy `node_aws_ccm` to `sdd-k8s-platform-node-role` in `terraform/modules/cluster-plumbing/main.tf` (mirrors `node_ebs_csi`, `Resource = "*"`): ec2 (AssociateRouteTable, CreateTags, CreateVolume, CreateNetworkInterface, DeleteNetworkInterface, DeleteSecurityGroup, DeleteVolume, DeregisterInstancesFromLoadBalancer, Describe*, DetachVolume, ModifyInstanceAttribute, RegisterInstancesWithLoadBalancer) + elasticloadbalancing (AddTags, CreateListener, CreateLoadBalancer, CreateTargetGroup, DeleteListener, DeleteLoadBalancer, DeleteTargetGroup, DescribeListeners, DescribeLoadBalancers, DescribeTags, DescribeTargetGroups, ModifyLoadBalancerAttributes, ModifyTargetGroup, RegisterTargets, RemoveTags, SetSecurityGroups, SetSubnets) + autoscaling (DescribeAutoScalingGroups)
- [x] T003 [Stage 1: Bootstrap] Add `null_resource.apply_aws_ccm` to `terraform/environments/dev/main.tf`: `depends_on = [null_resource.apply_app_frontend_ingress]`, `triggers.ccm_version = "aws-1.28.0"`, local-exec (bash interpreter) mirroring `apply_app_backend` — SSM command: (1) base64-apply `aws-ccm.yaml`, (2) `kubectl annotate svc ingress-nginx-controller -n ingress-nginx service.beta.kubernetes.io/aws-load-balancer-subnets='<%%PUBLIC_SUBNETS%%>' --overwrite` (replace with `join(",", module.vpc.public_subnet_ids)`), (3) `kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T004 [Stage 2: Verify] Static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY: 1 new IAM policy + 1 new null_resource (zero changes to existing resources)
- [ ] T005 [Stage 2: Verify] AC-001/AC-002: CCM rolled out + 1 pod Running (0 restarts)
- [ ] T006 [Stage 2: Verify] AC-003/AC-004: `ingress-nginx-controller` EXTERNAL-IP = ELB DNS (not `<pending>`) + Ingress ADDRESS populated
- [ ] T007 [Stage 2: Verify] AC-005: annotation shows the public subnet IDs (internet-facing ELB)
