# Spec: Pre-Destroy CCM ELB Cleanup

**Feature Branch**: `004-12-pre-destroy-elb-cleanup` | **Date**: 2026-09-16 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions workflow only (`.github/workflows/terraform-destroy.yml`) — no Terraform code changes
- **Kubernetes / Cluster Scope**: none (the CCM and its ELB are already gone by destroy time)
- **Target Services / Modules**: `.github/workflows/terraform-destroy.yml` (add one step before `terraform destroy`)
- **Security & CI/CD**: existing OIDC role chain (bootstrap → assume role); the assume role's `PowerUserAccess` already grants `elasticloadbalancing:*` + `ec2:Describe*`
- **Root Cause**: the CCM creates a Classic ELB out-of-band (via the `ingress-nginx-controller` LoadBalancer Service). That ELB is not a Terraform resource, so Terraform's destroy graph is unaware of it. The ELB places ENIs in the public subnets (via the `aws-load-balancer-subnets` annotation). On `terraform destroy`, Terraform cannot delete `aws_subnet.public[*]` or `aws_internet_gateway.this` while the ELB's ENIs occupy the subnets → destroy hangs ~20 min → fails. Manually deleting the ELB releases the ENIs; a re-run then succeeds. This is the "orphaned ELBs from prior cluster recreations" side-effect listed under 004-11's Out of Scope.

### 1.1 Workflow Contract (GitHub Actions)

Add a **Pre-Destroy ELB Cleanup** step to `.github/workflows/terraform-destroy.yml`, positioned after `Terraform Init` and before `Terraform Destroy`. The step:

1. Resolves the VPC ID by its cluster tag (robust against partially-destroyed Terraform state):
   ```bash
   VPC_ID=$(aws ec2 describe-vpcs \
     --filters "Name=tag-key,Values=kubernetes.io/cluster/sdd-k8s-platform" \
     --query 'Vpcs[0].VpcId' --output text)
   ```
2. Lists all Classic ELBs in that VPC:
   ```bash
   LB_NAMES=$(aws elb describe-load-balancers \
     --query "LoadBalancerDescriptions[?VpcId=='${VPC_ID}'].LoadBalancerName" \
     --output text)
   ```
3. Deletes each ELB and waits for full deletion (ENI release) before proceeding:
   ```bash
   for LB in $LB_NAMES; do
     aws elb delete-load-balancer --load-balancer-name "$LB"
     for i in $(seq 1 30); do
       EXISTS=$(aws elb describe-load-balancers --load-balancer-names "$LB" \
         --query 'LoadBalancerDescriptions[0].LoadBalancerName' --output text 2>/dev/null) || EXISTS=""
       [ -z "$EXISTS" ] || [ "$EXISTS" = "None" ] && break
       sleep 10
     done
   done
   ```
- **Idempotency**: no ELBs → `LB_NAMES` is empty → the loop is a no-op. Safe to run on every destroy.
- **No Terraform change**: the fix is entirely in the workflow; `main.tf`, modules, and manifests are untouched.
- **No echo / validation statements**: per constitution P6, the step contains only the `aws` commands above — no `echo`, no `set -x`, no validation gates.

### 1.2 Terraform / HCL Resource Contracts
None (no Terraform code changes).

### 1.3 Kubernetes Manifest / Helm Values Contracts
None.

### 1.4 Data & Storage Contracts
None.

### 1.5 Network & Security Contracts
- **ELB type**: Classic ELB (`aws elb` API), not ALB/NLB (`aws elbv2`). The CCM creates a Classic ELB for the `ingress-nginx-controller` Service (no `aws-load-balancer-type: nlb` annotation).
- **VPC tag**: `kubernetes.io/cluster/sdd-k8s-platform=owned` (set by 004-4 on `aws_vpc.this`). Used to scope the ELB search to the correct VPC.
- **IAM**: the assume role (`github-actions-assume-role`) has `PowerUserAccess` (includes `elasticloadbalancing:*`, `ec2:Describe*`) + `TerraformIamAccess` (`iam:*`). No IAM change needed.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (grep-based, per 002-0 pattern):

- [ ] AC-001: Workflow YAML is valid (`actionlint .github/workflows/terraform-destroy.yml` exits 0)
- [ ] AC-002: The cleanup step is present in the workflow (grep for `Pre-Destroy ELB Cleanup` in `terraform-destroy.yml`)
- [ ] AC-003: The cleanup step runs BEFORE `terraform destroy` (grep: the `Pre-Destroy ELB Cleanup` step appears before the `Terraform Destroy` step in the file)
- [ ] AC-004: The cleanup step resolves the VPC by cluster tag (grep for `kubernetes.io/cluster/sdd-k8s-platform` in the cleanup step)
- [ ] AC-005: The cleanup step deletes Classic ELBs (grep for `aws elb delete-load-balancer` in the workflow)
- [ ] AC-006: The cleanup step waits for ELB deletion (grep for `aws elb describe-load-balancers` in the cleanup step, confirming the wait loop)
- [ ] AC-007: The workflow retains the type-`"destroy"` confirmation gate (grep for `github.event.inputs.confirm`)
- [ ] AC-008: No Terraform code changes (git diff shows only `.github/workflows/terraform-destroy.yml` modified)

## 3. Assumptions & Technical Constraints

- **ELB ownership**: the CCM creates and owns the ELB; Terraform has no `aws_lb` resource for it. The ELB is invisible to Terraform's dependency graph.
- **ELB type**: Classic ELB (`aws elb`), not ALB/NLB. The CCM creates a Classic ELB for the `ingress-nginx-controller` LoadBalancer Service.
- **VPC tag**: `kubernetes.io/cluster/sdd-k8s-platform=owned` is present on the VPC (set by 004-4). If the VPC is already destroyed, `VPC_ID` is empty and the step is a no-op (safe).
- **IAM**: the assume role has `PowerUserAccess` (includes `elasticloadbalancing:*` + `ec2:Describe*`). No IAM change needed.
- **Orphaned ELB security groups**: the CCM also creates an SG for the ELB. That SG is orphaned after the ELB is deleted but does NOT block the destroy (only ENIs block subnet deletion). Out of scope for this spec.
- **Orphaned ELBs from prior recreations**: the cleanup deletes ALL Classic ELBs in the VPC, not just the current one. This also handles the "orphaned ELBs from prior cluster recreations" side-effect (004-11 Out of Scope).
- **Testing Policy**: No unit or E2E test generation — validation via grep-based contract checks in CI (per 002-0 pattern).
- **Tooling**: `actionlint` for workflow YAML validation; no local AWS CLI or Terraform execution.
