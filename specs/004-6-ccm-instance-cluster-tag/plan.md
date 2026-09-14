# Architecture Delta: CCM Instance Cluster Tag

**Branch**: `004-6-ccm-instance-cluster-tag` | **Date**: 2026-09-13 | **Spec**: [specs/004-6-ccm-instance-cluster-tag/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/modules/control-plane/main.tf` | Modify | Add `"kubernetes.io/cluster/sdd-k8s-platform" = "owned"` to `aws_instance.control_plane` `tags` (line ~35). |
| `terraform/modules/worker-nodes/main.tf` | Modify | Add `"kubernetes.io/cluster/sdd-k8s-platform" = "owned"` to `aws_instance.worker` `tags` (line ~47). |

Two-file change. No new resource, no IAM, no manifest, no VPC change, no `null_resource` change.

## 2. Key Design Decisions

### 2.1 Why tag the **instance**, not the VPC
The 004-5 `--v=4` trace is decisive:
```
ec2 DescribeInstances (i-0efe35678d39e688c) → 200 OK
ec2 DescribeInstances (i-0efe35678d39e688c) → 200 OK
tags.go:95] Tag "KubernetesCluster" nor "kubernetes.io/cluster/..." not found
main.go:112] Cloud provider could not be initialized
```
**No `DescribeSubnets` or `DescribeVpcs` calls.** The CCM's `ClusterID()` init reads the `kubernetes.io/cluster/<name>` tag from the **instance's tags** (returned in the `DescribeInstances` response), not from the VPC. 004-4 tagged the **VPC** — the wrong resource. The instance (the CCM's worker `i-0efe35678d39e688c`) has no cluster tag → "tag not found" → fatal.

### 2.2 Why tag **both** control plane and workers
The CCM runs on a **worker** (`ip-10-0-12-65`), so the worker tag is the one that unblocks it. The control plane is tagged for consistency (the CCM could be rescheduled there, and other tooling may expect the tag on all cluster nodes). Both use the same `merge(var.tags, {...})` pattern, so the addition is uniform.

### 2.3 In-place update, no instance replacement
`tags` is an **updatable** attribute on `aws_instance` — Terraform does an in-place `aws ec2 create-tags` (no replacement, no reboot, no data loss). The plan delta is exactly the tag updates on the 3 instances (1 control plane + 2 workers).

### 2.4 No `null_resource` re-run needed
The CCM pod is **already crash-looping** (it fatal-exits ~7s after each start). The tag change is on the EC2 instance, not the pod. On the CCM's **next natural restart** (CrashLoopBackOff backoff), it will call `DescribeInstances`, read the now-present cluster tag, and succeed. No `apply_aws_ccm` re-run is required.

**Verification timing note:** after 29+ restarts the backoff is at the max (~5 min), so the next natural restart may be up to 5 min after the tag is applied. To verify faster, the user can force an immediate restart:
```
kubectl delete pod -n kube-system -l app=aws-cloud-controller-manager
```
This is a manual step (not a Terraform change) — it makes AC-005/AC-006 deterministic and fast.

### 2.5 What stays
- **VPC tag** (004-4) — stays. Harmless; may be used by other tooling.
- **CCM `--v=4`** (004-5) — stays. Useful for future diagnostics.
- **CCM version** — unchanged (`v1.28.11-eks-1-28-64`).

## 3. Rollout Stages

1. **Terraform apply** — in-place tag update on 3 instances (control plane + 2 workers). No replacement.
2. **CCM restart** — natural (CrashLoopBackOff backoff) or manual (`kubectl delete pod`). The CCM reads the now-present tag and reaches Ready.
3. **ELB creation** — the CCM (now Ready) creates the LoadBalancer for `ingress-nginx-controller` → EXTERNAL-IP populated → Ingress ADDRESS populated.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan shows ONLY the instance tag updates (AC-001/AC-002)
- **Tag Validation**: `aws ec2 describe-instances` confirms the cluster tag on the control plane + workers (AC-003/AC-004)
- **CCM Validation**: `kubectl get pods` + `kubectl rollout status` confirm the CCM is Ready (AC-005/AC-006)
- **ELB Validation**: `kubectl get svc` + `kubectl get ingress` confirm EXTERNAL-IP + ADDRESS populated (AC-007/AC-008)

## 5. Risks / Notes

- **No collateral plan changes**: the only config delta is the `tags` map on 3 `aws_instance` resources; all other resources are untouched.
- **In-place, safe**: tag updates are non-disruptive (no instance replacement, no reboot).
- **Downstream unblock**: once the CCM is Ready, 004-4's AC-003/004/005 (EXTERNAL-IP, Ingress ADDRESS, public-subnet annotation) become verifiable. The annotation (AC-005) is already applied.
- **If the CCM still fails after the tag is applied** (unlikely given the trace) → the `--v=4` logs (still enabled) will show the next failure point; scope a follow-on spec.
