# Architecture Delta: Pre-Destroy CCM ELB Cleanup

**Branch**: `004-12-pre-destroy-elb-cleanup` | **Date**: 2026-09-16 | **Spec**: [specs/004-12-pre-destroy-elb-cleanup/spec.md](spec.md)

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-destroy.yml` | Modify | Add a `Pre-Destroy ELB Cleanup` step (after `Terraform Init`, before `Terraform Destroy`) that resolves the VPC by cluster tag, lists Classic ELBs in that VPC, deletes each, and waits for ENI release before `terraform destroy` runs. |

**No other files change.** No Terraform code, no modules, no manifests, no bootstrap scripts, no IAM, no VPC/SG. The fix is entirely a workflow step.

## 2. Architectural Boundaries & Dependency Flow

- **Terraform-managed layer** (destroyed by `terraform destroy`): VPC, subnets, IGW, NAT, route tables, EC2 instances, IAM, SSM parameters. Terraform's dependency graph is unaware of the CCM-created ELB.
- **CCM-managed layer** (NOT in Terraform's graph): the Classic ELB for the `ingress-nginx-controller` LoadBalancer Service, its ENIs in the public subnets, and its security group. The CCM creates these out-of-band via the AWS API.
- **The destroy conflict**: the ELB's ENIs occupy the public subnets. Terraform cannot delete `aws_subnet.public[*]` or `aws_internet_gateway.this` while those ENIs exist → destroy hangs ~20 min → fails. The CCM is already gone (its pod was destroyed with the cluster), so nothing will ever clean up the ELB.
- **The fix boundary**: a workflow step that runs *before* `terraform destroy` and deletes the CCM-created ELBs, releasing the ENIs so Terraform can proceed. This is a **teardown-time** concern, not a provisioning-time one — it does not change how the cluster is built, only how it is torn down.
- **Dependency flow (destroy)**: `Terraform Init` → **`Pre-Destroy ELB Cleanup` (new)** → `Terraform Destroy`. The cleanup step is idempotent (no ELBs → no-op) and safe to run on every destroy.

## 3. Provisioning & Rollout Stages

This is a **teardown** fix, not a provisioning change. The destroy sequence becomes:

1. **Stage 1 - Confirm**: the `type-"destroy"` confirmation gate (unchanged).
2. **Stage 2 - Terraform Init**: `terraform init -backend-config=...` (unchanged).
3. **Stage 3 - Pre-Destroy ELB Cleanup (NEW)**: resolve VPC by `kubernetes.io/cluster/sdd-k8s-platform` tag → list Classic ELBs in that VPC → `aws elb delete-load-balancer` each → wait for deletion (ENI release). No-op if no ELBs.
4. **Stage 4 - Terraform Destroy**: `terraform destroy -auto-approve` (unchanged) — now succeeds because the ELB ENIs no longer block the subnets/IGW.

## 4. Verification Gates

Per constitution P5/P6, all gates are machine-verifiable in CI/CD (grep/actionlint, no local tooling):

- **Workflow Lint**: `actionlint .github/workflows/terraform-destroy.yml` → exit 0
- **Step Presence**: grep `terraform-destroy.yml` for `Pre-Destroy ELB Cleanup` → present
- **Step Ordering**: grep confirms `Pre-Destroy ELB Cleanup` appears before `Terraform Destroy` in the file
- **VPC Scoping**: grep for `kubernetes.io/cluster/sdd-k8s-platform` in the cleanup step
- **ELB Delete**: grep for `aws elb delete-load-balancer` → present
- **Deletion Wait**: grep for `aws elb describe-load-balancers` in the cleanup step (the wait loop)
- **Confirmation Gate Retained**: grep for `github.event.inputs.confirm` → present
- **No Terraform Drift**: `git diff --name-only` shows only `.github/workflows/terraform-destroy.yml` modified

## 5. Key Decisions

- **Workflow step, not Terraform code**: the ELB is not a Terraform resource, so no Terraform change can fix this. A pre-destroy workflow step is the minimal, self-contained fix.
- **VPC-by-tag, not Terraform state**: resolving the VPC by its `kubernetes.io/cluster/sdd-k8s-platform` tag is robust against partially-destroyed state (where `terraform output` may already be empty). If the VPC is already gone, the step is a no-op.
- **Classic ELB API (`aws elb`), not `aws elbv2`**: the CCM creates a Classic ELB for the `ingress-nginx-controller` Service (confirmed by the diagnostic `aws elb describe-load-balancers` returning targets). No `aws-load-balancer-type: nlb` annotation is set.
- **Delete ALL ELBs in the VPC**: not just the current one — this also sweeps the orphaned ELBs from prior cluster recreations (the 004-11 Out-of-Scope side-effect).
- **Wait for deletion, not just issue the delete**: `aws elb delete-load-balancer` is async; the ENIs are only released once the ELB is fully gone. The wait loop (up to 5 min) ensures the subnets are free before `terraform destroy` starts.
- **No echo / validation statements**: per constitution P6, the step contains only the `aws` commands — no `echo`, no `set -x`, no validation gates.
- **Orphaned CCM ELB security group is out of scope**: the CCM also creates an SG for the ELB. It is orphaned after the ELB is deleted but does NOT block the destroy (only ENIs block subnet deletion). Cleaning it up is a separate concern.
