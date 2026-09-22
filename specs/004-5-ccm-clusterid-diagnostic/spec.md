---
name: 004-5-ccm-clusterid-diagnostic
description: Add --v=4 verbose logging to the CCM and capture its startup logs to diagnose the ClusterID init failure (tag not found) after all external factors were ruled out.
date: 2026-09-13
status: Implemented
---

# Spec: CCM ClusterID Diagnostic (Verbose Logging)

**Feature Branch**: `004-5-ccm-clusterid-diagnostic` | **Date**: 2026-09-13 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources, no IAM, no new manifest)
- **Kubernetes / Cluster Scope**: `aws-cloud-controller-manager` Deployment (`kube-system`) — add `--v=4` verbose logging; capture its startup logs
- **Target Services / Modules**: `terraform/environments/dev/manifests/aws-ccm.yaml` + `null_resource.apply_aws_ccm` in `terraform/environments/dev/main.tf`
- **Root Cause (unresolved — this spec is the diagnostic)**: The CCM crash-loops with `tags.go:95: Tag "KubernetesCluster" nor "kubernetes.io/cluster/..." not found` → `main.go:112: AWS cloud failed to find ClusterID`. Every external factor has been ruled out from the worker node (`i-0efe35678d39e688c`, the node the CCM runs on):
  - The tag **is** on the cluster VPC `vpc-00004ff9a1efc205c` (`kubernetes.io/cluster/sdd-k8s-platform=owned`) ✅
  - The worker **is** in the cluster VPC (subnet `subnet-0eabfb4c0fd3750c8`) ✅
  - The worker's IMDS returns the correct instance ID ✅
  - From the worker, `DescribeInstances` → correct subnet → `DescribeSubnets` → correct VPC → `DescribeVpcs` shows the tag ✅
  - The worker has the node profile (`sdd-k8s-platform-node-profile`) ✅

  Yet the CCM (same node, same credentials) still fails. The only remaining explanation is that the CCM's internal AWS call path differs from the manual test. `--v=4` logs every AWS API call the CCM makes, revealing exactly which call fails (or which VPC it actually queries).

## 2. Infrastructure Contracts

### 2.1 CCM Manifest (Modify — `manifests/aws-ccm.yaml`)
- **Target**: `aws-cloud-controller-manager` Deployment `args`
- **Change**: append `--v=4` to the existing args (`--cloud-provider=aws --configure-cloud-routes=false --cluster-name=sdd-k8s-platform --v=4`)
- **Why `--v=4`**: glog verbosity 4 makes the AWS cloud provider log each `DescribeInstances` / `DescribeSubnets` / `DescribeVpcs` call and its result, plus any `AccessDenied`. This is the standard CCM diagnostic.

### 2.2 Apply Command (Modify — `dev/main.tf`, `apply_aws_ccm`)
- **Target**: the SSM `--parameters` command string
- **Change**: replace the trailing `kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s` (which **times out** while the CCM crash-loops, failing the provisioner) with a log capture:
  ```
  ... && kubectl rollout restart deployment/aws-cloud-controller-manager -n kube-system && sleep 30 && (kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 --previous || kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200)
  ```
- **Why**: the CCM never becomes Ready (it crash-loops), so `rollout status` can't succeed. Instead, restart the pod, wait 30s for it to start and crash (emitting the `--v=4` trace), then dump the logs. `--previous` captures the last crashed container's output (the CCM fatal-exits ~7s after start, so one crash cycle fits in 30s); the `||` fallback handles the case where the new pod hasn't crashed yet (no previous container — `--previous` is also incompatible with `--all-containers`, so neither is used). The SSM invocation output now **contains the CCM's AWS call trace** — the diagnostic evidence.
- **Re-run mechanism**: add a new trigger `ccm_log_level = "4"` to `apply_aws_ccm.triggers` (the triggers map change forces the provisioner re-run; the manifest change alone is embedded in the command and is not a trigger).
- **Unchanged**: `depends_on`, the SSM-agent wait, the bootstrap-instance-id gate, the poll loop, `--timeout-seconds 600`, the Service annotation step.

### 2.3 No Other Changes
- No new `null_resource`, no IAM, no module changes, no other manifest edits.

## 3. Acceptance Criteria

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows only the `apply_aws_ccm` re-run
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2; plan shows exactly 1 `null_resource.apply_aws_ccm` to be replaced, zero other changes

- [ ] AC-003: CCM manifest contains the verbose flag
  ```
  grep -c '\-\-v=4' terraform/environments/dev/manifests/aws-ccm.yaml
  ```
  **Expected**: `1`

- [ ] AC-004: The apply succeeds and the SSM output contains the CCM's `--v=4` AWS call trace
  ```
  # After the terraform-apply run, fetch the SSM invocation output for the 004-5 command:
  aws ssm get-command-invocation --instance-id <CP_ID> --command-id <CMD_ID> \
    --query "{stdout:StandardOutputContent}" --output json
  ```
  **Expected**: stdout contains the CCM startup trace — `Loading region from metadata service`, `Building AWS cloudprovider`, and the `DescribeInstances` / `DescribeSubnets` / `DescribeVpcs` calls (or an `AccessDenied` / the VPC ID the CCM actually queried)

- [ ] AC-005: Root cause identified from the trace
  **Expected**: the `--v=4` output shows the exact failing AWS call (e.g. an `AccessDenied` on a specific action, or the CCM querying the default VPC `vpc-0d8b8ee0196e2731c` instead of the cluster VPC). This output drives the follow-on fix spec (004-6).

## 4. Out of Scope
- No fix to the ClusterID root cause (that is 004-6, scoped from the AC-004/AC-005 evidence)
- No IAM changes (the node role already has `ec2:Describe*`; if the trace shows an `AccessDenied`, 004-6 addresses it)
- No CCM version change (stays on `v1.28.11-eks-1-28-64`)
- No ELB / Ingress ADDRESS verification (blocked until the CCM is fixed)

## 5. Downstream Consumer
- **004-6 (fix)** — scoped from the AC-004/AC-005 trace: corrects the CCM's ClusterID discovery (IAM action, VPC tag, or CCM arg) so the CCM reaches Ready and the `ingress-nginx-controller` LoadBalancer gets an EXTERNAL-IP (004-4 AC-003/004/005)
