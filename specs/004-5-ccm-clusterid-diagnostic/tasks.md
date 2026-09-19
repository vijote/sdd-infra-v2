# Execution Graph (DAG): CCM ClusterID Diagnostic (Verbose Logging)

**Input**: Design documents from `/specs/004-5-ccm-clusterid-diagnostic/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Manifest] In `terraform/environments/dev/manifests/aws-ccm.yaml`: append `- --v=4` to the CCM Deployment `args` list (after `- --cluster-name=sdd-k8s-platform`, line ~88) — glog verbosity 4 logs every AWS API call (DescribeInstances/DescribeSubnets/DescribeVpcs) + any AccessDenied
- [x] T002 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`: in `null_resource.apply_aws_ccm` (a) add `ccm_log_level = "4"` to `triggers` (line ~496); (b) in the SSM `--parameters` command string (line ~539), replace the trailing `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s` with `sleep 30 && (KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 --previous || KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200)` — keep the existing `kubectl rollout restart` step; the apply now succeeds (log capture exits 0) and the SSM output contains the CCM's `--v=4` AWS call trace (Depends on T001)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T003 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001, T002)
- [x] T004 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows exactly 1 `null_resource.apply_aws_ccm` re-run, zero other changes (Depends on T001, T002)
- [x] T005 [Stage 2: Verify] AC-003: `grep -c '\-\-v=4' terraform/environments/dev/manifests/aws-ccm.yaml` returns `1` (Depends on T001)
- [x] T006 [Stage 2: Verify] AC-004/AC-005: after the next `terraform-apply` run — SSM invocation output contains the CCM `--v=4` trace (region load, cloudprovider build, DescribeInstances/DescribeSubnets/DescribeVpcs calls or AccessDenied) and the root cause is identified (failing AWS action, or wrong VPC queried) → scope 004-6 (Depends on T001, T002)
