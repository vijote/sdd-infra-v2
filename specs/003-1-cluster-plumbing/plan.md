# Architecture Delta: Cluster Plumbing (Security Groups + IAM)

**Branch**: `003-1-cluster-plumbing` | **Date**: 2026-09-05 | **Spec**: specs/003-1-cluster-plumbing/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/cluster-plumbing/main.tf` | Create | Control plane SG (6443, 2379-2380, 22 from VPC CIDR), worker SG (10250, 30000-32767, 22 from VPC CIDR), IAM role (SSM + ECR read-only), IAM instance profile |
| `terraform/modules/cluster-plumbing/variables.tf` | Create | Input variables (vpc_id, vpc_cidr, tags) |
| `terraform/modules/cluster-plumbing/outputs.tf` | Create | Exported outputs (control_plane_security_group_id, worker_security_group_id, node_iam_instance_profile_name) |
| `terraform/modules/cluster-plumbing/versions.tf` | Create | Terraform >= 1.5.0, AWS provider >= 5.0.0, provider config |
| `terraform/environments/dev/main.tf` | Modify | Add `module "cluster_plumbing"` (vpc_id = `module.vpc.vpc_id`, vpc_cidr = `var.vpc_cidr`) |
| `terraform/environments/dev/outputs.tf` | Modify | Add root outputs (control_plane_security_group_id, worker_security_group_id, node_iam_instance_profile_name) for 003-2/003-3 |

## 2. Architectural Boundaries & Dependency Flow

- **Upstream**: `002-vpc-foundation` provides `vpc_id` (via `module.vpc.vpc_id`) and `vpc_cidr` (via `var.vpc_cidr`)
- **Downstream**: `003-2-control-plane` + `003-3-worker-nodes` consume the SG IDs and instance profile name
- **Security Groups**: Control plane SG ingress 6443/2379-2380/22 from VPC CIDR only; worker SG ingress 10250/30000-32767/22 from VPC CIDR only; both egress all
- **IAM**: Role with `AmazonSSMManagedInstanceCore` + `AmazonEC2ContainerRegistryReadOnly` managed policies; instance profile attaches the role (no inline wildcard policies, no static credentials)
- **Out of Scope**: No EC2 instances, no kubeadm, no CNI — plumbing only
- **Shared Dependencies**: AWS provider >= 5.0.0, Terraform >= 1.5.0, S3 state backend from `001-state-backend`

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC (workflow-applied)**: Create the cluster-plumbing module + dev environment wiring. Deployment is performed by the existing `.github/workflows/terraform-apply.yml` on main push (`terraform apply -auto-approve` in `terraform/environments/dev`) — no local apply, no new workflow
2. **Stage 2 - Verification (CI-only)**: Validate deployed SGs and IAM via AWS CLI in the GitHub Actions workflow — no local AWS CLI execution

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — AC-001, AC-002
- **Control Plane SG**: `aws ec2 describe-security-groups --group-ids $(terraform output -raw control_plane_security_group_id) --query 'SecurityGroups[0].IpPermissions[?FromPort==`6443`].CidrIpv4' --output text | grep -q '10.0.0.0/16'` — AC-003
- **Worker SG**: `aws ec2 describe-security-groups --group-ids $(terraform output -raw worker_security_group_id) --query 'SecurityGroups[0].IpPermissions[?FromPort==`30000`].CidrIpv4' --output text | grep -q '10.0.0.0/16'` — AC-004
- **Instance Profile**: `aws iam get-instance-profile --instance-profile-name $(terraform output -raw node_iam_instance_profile_name) --query 'InstanceProfile.Roles[0].Arn' --output text | grep -q 'arn:aws:iam'` — AC-005
- **SSM Policy**: `aws iam list-attached-role-policies --role-name <role> --query 'AttachedPolicies[?PolicyName==`AmazonSSMManagedInstanceCore`].PolicyName' --output text | grep -q 'AmazonSSMManagedInstanceCore'` — AC-006
