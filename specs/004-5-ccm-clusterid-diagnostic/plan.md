# Architecture Delta: CCM ClusterID Diagnostic (Verbose Logging)

**Branch**: `004-5-ccm-clusterid-diagnostic` | **Date**: 2026-09-13 | **Spec**: [specs/004-5-ccm-clusterid-diagnostic/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/manifests/aws-ccm.yaml` | Modify | Append `- --v=4` to the CCM Deployment `args` (after `--cluster-name=sdd-k8s-platform`, line ~88). glog verbosity 4 → logs every AWS API call + any `AccessDenied`. |
| `terraform/environments/dev/main.tf` | Modify | In `null_resource.apply_aws_ccm`: (a) add trigger `ccm_log_level = "4"` (line ~496); (b) in the SSM `--parameters` command (line ~539), replace the trailing `kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=300s` with `sleep 30 && (kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 --previous \|\| kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200)`. The existing `kubectl rollout restart` is **kept** (it already precedes the `rollout status`). |

Two-file change. No new resource, no IAM, no module, no CCM version change.

## 2. Key Design Decisions

### 2.1 Why `--v=4` (and not a fix)
Every external factor is ruled out (tag on VPC, worker in cluster VPC, IMDS ID, manual `DescribeInstances→DescribeSubnets→DescribeVpcs` chain from the worker, node profile). The CCM's internal AWS call path is the only untested variable. `--v=4` is the standard CCM diagnostic: it logs each `DescribeInstances` / `DescribeSubnets` / `DescribeVpcs` call and result, plus any `AccessDenied`. This spec **captures the evidence**; the fix is 004-6, scoped from the trace.

### 2.2 Why replace `rollout status` with a log capture
The CCM never becomes Ready (it crash-loops on `ClusterID`), so `kubectl rollout status --timeout=300s` **always times out** → the provisioner exits 1 → the apply fails. The diagnostic needs the CCM's startup logs, not a successful rollout. So: keep the existing `rollout restart` (forces a fresh pod with `--v=4`), `sleep 30` (the CCM fatal-exits ~7s after start, so one crash cycle fits), then dump the logs.

### 2.3 Log capture: `--previous` with `||` fallback
- `kubectl logs --previous` shows the **last crashed** container's output — the `--v=4` trace ends in the fatal `main.go:112` line, which is what we need.
- `--previous` is **incompatible** with `--all-containers` (kubectl rejects the combo), so neither is used; the single-container CCM pod needs no `--all-containers`.
- The `||` fallback covers the edge case where the new pod hasn't crashed yet (no previous container) — it then dumps the current container's (partial) startup logs. Either way the SSM output contains the AWS call trace.
- `(a || b)` is valid bash inside the single `&&`-chained SSM string (AWS-RunShellScript short-circuit gotcha preserved).

### 2.4 Re-run mechanism (003-6)
Adding `ccm_log_level = "4"` to `triggers` changes the provisioner's computed configuration → Terraform re-runs `apply_aws_ccm` on the next apply. The manifest change is embedded in the command (base64) and is not itself a trigger, so the explicit trigger is required.

## 3. SSM Command Flow (local-exec, after change)

Single `&&`-chained command on the control plane (gated on SSM-agent registration + `kubeadm-bootstrap-instance-id`, per 003 pattern — unchanged):

1. `kubectl annotate svc ingress-nginx-controller -n ingress-nginx service.beta.kubernetes.io/aws-load-balancer-subnets='<public-subnets>' --overwrite`  (unchanged)
2. `echo '<base64 aws-ccm.yaml, now with --v=4>' | base64 -d | kubectl apply -f -`  (manifest now carries `--v=4`)
3. `kubectl rollout restart deployment/aws-cloud-controller-manager -n kube-system`  (kept — fresh pod with `--v=4`)
4. `sleep 30`  ← **new** (let the pod start + crash, emitting the trace)
5. `(kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 --previous || kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200)`  ← **new** (replaces `rollout status`)

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show ONLY the `apply_aws_ccm` re-run (AC-001/AC-002)
- **Manifest Validation**: `grep -c '\-\-v=4' terraform/environments/dev/manifests/aws-ccm.yaml` returns `1` (AC-003)
- **Evidence Gate**: after the `terraform-apply` run, the SSM invocation output contains the CCM `--v=4` AWS call trace (AC-004) → root cause identified (AC-005) → drives 004-6

## 5. Risks / Notes

- **No collateral plan changes**: the only config deltas are the CCM `args` (manifest) and the `apply_aws_ccm` command + trigger; all other resources are untouched.
- **The apply will still "succeed"** (provisioner exits 0) even though the CCM is crash-looping — the log capture returns 0. That's intentional: this spec's job is to surface the trace, not to fix the CCM.
- **Downstream**: 004-4's AC-003/004/005 (EXTERNAL-IP, Ingress ADDRESS, public-subnet annotation) remain blocked until 004-6 fixes the CCM. The annotation (AC-005) is already applied and verifiable independently.
- **If the trace shows an `AccessDenied`** on a specific EC2/ELB action → 004-6 adds that action to `node_aws_ccm`. **If it shows the CCM querying the default VPC** → 004-6 addresses the VPC-discovery path (e.g. an explicit `--vpc-id` or tag fix).
