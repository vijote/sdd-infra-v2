# Execution Graph (DAG): CCM Instance Cluster Tag

**Input**: Design documents from `/specs/004-6-ccm-instance-cluster-tag/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 6 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] In `terraform/modules/control-plane/main.tf`: add `"kubernetes.io/cluster/sdd-k8s-platform" = "owned"` to the `aws_instance.control_plane` `tags` map (line ~35, alongside `Name = "sdd-k8s-control-plane"`) — the CCM's `ClusterID()` init reads the cluster tag from the instance's tags (004-5 trace: DescribeInstances → tags.go:95, no DescribeSubnets/DescribeVpcs)
- [x] T002 [Stage 1: Terraform] In `terraform/modules/worker-nodes/main.tf`: add `"kubernetes.io/cluster/sdd-k8s-platform" = "owned"` to the `aws_instance.worker` `tags` map (line ~47, alongside `Name = "sdd-k8s-${each.key}"`) — the CCM runs on a worker, so this is the tag that unblocks it; control plane tagged for consistency

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001, T002)
- [ ] T004 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows in-place tag updates on `aws_instance.control_plane` + `aws_instance.worker` (2 instances), zero other changes, no replacement (Depends on T001, T002)
- [ ] T005 [Stage 2: Verify] AC-003/AC-004: after the next `terraform-apply` run — `aws ec2 describe-instances` confirms `kubernetes.io/cluster/sdd-k8s-platform=owned` on the control plane instance and both worker instances (Depends on T001, T002)
- [ ] T006 [Stage 2: Verify] AC-005/AC-006: `kubectl get pods -n kube-system -l app=aws-cloud-controller-manager` shows 1 pod `1/1 Running` (0 restarts) + `kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s` succeeds — force an immediate restart if the CrashLoopBackOff backoff is at the ~5-min max: `kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager` (Depends on T001, T002)
- [ ] T007 [Stage 2: Verify] AC-007/AC-008: `kubectl get svc -n ingress-nginx ingress-nginx-controller` shows EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`) + `kubectl get ingress -n sdd-apps app-ingress` shows ADDRESS = ELB DNS name (not empty) — 004-4's previously-blocked ACs (Depends on T001, T002)
