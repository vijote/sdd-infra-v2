# Spec: Node Role SSM Permissions

**Feature Branch**: `003-0-node-role-ssm-permissions` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: IAM policy addition only — no new AWS resources
- **Kubernetes / Cluster Scope**: None
- **Target Service**: `sdd-k8s-platform-node-role` (EKS node instance profile role, created by 003-1-cluster-plumbing)
- **Root Cause**: The node role (003-1) has only `AmazonSSMManagedInstanceCore` + `AmazonEC2ContainerRegistryReadOnly`. `AmazonSSMManagedInstanceCore` lets the SSM agent *receive* commands but does NOT allow the node to *write* or *read* Parameter Store. 003-2's control plane bootstrap publishes the `kubeadm join` command via `aws ssm put-parameter` (would 403); 003-3's worker bootstrap reads it via `aws ssm get-parameter` (would 403).
- **Decision**: Add a scoped inline policy granting `ssm:PutParameter` + `ssm:GetParameter` on `/sdd-k8s-platform/*` parameters only.

### 1.1 Terraform / HCL Resource Contract

File: `terraform/modules/cluster-plumbing/main.tf`

Add one inline policy to the existing `aws_iam_role.node` resource (alongside the two managed-policy attachments):

```hcl
resource "aws_iam_role_policy" "node_ssm_parameters" {
  name = "sdd-k8s-platform-node-ssm-parameters"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:*:*:parameter/sdd-k8s-platform/*"
    }]
  })
}
```

- **`aws_iam_role.node`**: unchanged (name, trust policy, tags)
- **Existing managed attachments** (`node_ssm`, `node_ecr`): unchanged
- **Instance profile**: unchanged (same profile, now inherits the new inline policy)
- **No other resource changes** in the module

### 1.2 Deployment Contract

- **Method**: Existing `.github/workflows/terraform-apply.yml` on main push — no new workflow, no local apply (constitution principles 5, 6, 8)
- **Effect**: In-place update of `sdd-k8s-platform-node-role` (adds inline policy); the instance profile and any running nodes are unaffected until next launch
- **Rollback**: Remove the `aws_iam_role_policy.node_ssm_parameters` resource and re-apply

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates the inline policy (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Inline policy attached to the live role (`aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'ssm:PutParameter'`)
- [ ] AC-004: Policy grants both actions on the scoped resource (`aws iam get-role-policy --role-name sdd-k8s-platform-node-role --policy-name sdd-k8s-platform-node-ssm-parameters --query 'RolePolicy.PolicyDocument.Statement[0].Resource[0]' --output text | grep -q 'parameter/sdd-k8s-platform/\*'`)

## 3. Assumptions & Constraints

- **Scope**: `ssm:PutParameter` + `ssm:GetParameter` on `parameter/sdd-k8s-platform/*` only — least privilege for the join-command channel; no wildcard over all SSM
- **Shared profile**: The control plane (003-2) and workers (003-3) use the same instance profile, so both the publish (Put) and read (Get) paths are covered by this single role change
- **Ordering**: This spec MUST be applied before 003-2's control plane launches, or the `put-parameter` step in its user-data 403s
- **No state impact on existing nodes**: Adding an inline policy does not replace the role or profile; already-running instances keep their current credentials until relaunched
