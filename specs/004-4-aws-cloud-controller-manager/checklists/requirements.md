# Technical Quality Checklist: AWS Cloud Controller Manager (CCM)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: `004-4-aws-cloud-controller-manager`

## Infrastructure Contracts
- [x] CHK001: CCM version pinned to `v1.28.x` (matches cluster K8s 1.28.0 minor)
- [x] CHK002: CCM runs as a single-replica Deployment in `kube-system` (leader-elected)
- [x] CHK003: CCM uses the node instance profile via IMDS (no IRSA — kubeadm has no OIDC provider)
- [x] CHK004: `--configure-cloud-routes=false` (Flannel uses VXLAN, not cloud routes — prevents CCM route conflicts)
- [x] CHK005: `--cluster-name=sdd-k8s-platform` (matches the cluster identity)

## IAM / Security
- [x] CHK006: Node role gains a scoped inline policy (`node_aws_ccm`) mirroring the `node_ebs_csi` pattern
- [x] CHK007: IAM actions cover ELB lifecycle + EC2 describe/tag (per official AWS CCM policy)
- [x] CHK008: `Resource = "*"` (dev-only, matches `node_ebs_csi` scope — no over-scoping)

## Networking / Load Balancer
- [x] CHK009: Ingress Service annotated with `aws-load-balancer-subnets` = public subnet IDs
- [x] CHK010: Public subnet IDs injected via `%%TOKEN%%` replace (007 pattern) — forces internet-facing ELB
- [x] CHK011: Annotation targets the `ingress-nginx-controller` Service in `ingress-nginx`

## Terraform / Apply
- [x] CHK012: `null_resource.apply_aws_ccm` mirrors the `apply_app_backend` pattern
- [x] CHK013: `depends_on = [null_resource.apply_app_frontend_ingress]` (CCM runs after all workloads + ingress Service)
- [x] CHK014: `triggers.ccm_version` re-runs the provisioner on version change
- [x] CHK015: SSM command applies manifest + annotates Service + waits for rollout (single `&&`-chained command)

## Acceptance Criteria
- [x] CHK016: All 5 ACs are machine-verifiable via `kubectl` (rollout status, get pods, get svc, get ingress, jsonpath annotation)
- [x] CHK017: AC-003/AC-004 confirm the ELB DNS name appears (not `<pending>`)
- [x] CHK018: AC-005 confirms the ELB is internet-facing (public subnets)
