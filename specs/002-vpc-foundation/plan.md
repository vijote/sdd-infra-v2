# Architecture Delta: VPC Foundation

**Branch**: `002-vpc-foundation` | **Date**: 2026-09-05 | **Spec**: specs/002-vpc-foundation/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/vpc/main.tf` | Create | VPC, 3 public + 3 private subnets, IGW, single NAT GW (public subnet 1), EIP, 2 route tables, 6 associations |
| `terraform/modules/vpc/variables.tf` | Create | Input variables (region, vpc_cidr, availability_zones, tags) |
| `terraform/modules/vpc/outputs.tf` | Create | Exported outputs (vpc_id, public_subnet_ids, private_subnet_ids, nat_gateway_id) |
| `terraform/modules/vpc/versions.tf` | Create | Terraform >= 1.5.0, AWS provider >= 5.0.0, provider config |
| `terraform/environments/dev/main.tf` | Modify | Add `module "vpc"` instantiation (source `../../modules/vpc`) |
| `terraform/environments/dev/variables.tf` | Modify | Add `vpc_cidr` (default `10.0.0.0/16`), `availability_zones` (default 3 AZs) |
| `terraform/environments/dev/outputs.tf` | Create | Root outputs (vpc_id, private_subnet_ids) for downstream phases |

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: VPC `10.0.0.0/16`, public subnets `10.0.1.0/24`-`10.0.3.0/24`, private subnets `10.0.11.0/24`-`10.0.13.0/24`, IGW, single NAT GW in `10.0.1.0/24`
- **Routing**: Public route table (0.0.0.0/0 → IGW) for 3 public subnets; private route table (0.0.0.0/0 → NAT GW) for 3 private subnets
- **Out of Scope (deferred)**: Security groups → `003-1-cluster-plumbing`; CI/CD IAM roles → CloudFormation (`000-8-cloudformation-circular-dependency-fix`)
- **Downstream Consumers**: `003-1-cluster-plumbing` (SGs), `003-2-control-plane` and `003-3-worker-nodes` (EC2) consume `vpc_id` + `private_subnet_ids`
- **Shared Dependencies**: AWS provider >= 5.0.0, Terraform >= 1.5.0, S3 state backend from `001-state-backend`

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC (workflow-applied)**: Create the VPC module + dev environment wiring. Deployment is performed by the existing `.github/workflows/terraform-apply.yml` on main push (`terraform apply -auto-approve` in `terraform/environments/dev`) — no local apply, no new workflow
2. **Stage 2 - Verification (CI-only)**: Validate deployed resources against AC-003 through AC-007 via AWS CLI in the GitHub Actions workflow — no local AWS CLI execution

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode`
- **VPC CIDR**: `aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id) --query 'Vpcs[0].CidrBlock' --output text | grep -q '10.0.0.0/16'`
- **Subnet Count**: `aws ec2 describe-subnets --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(Subnets)' --output text | grep -q '^6$'`
- **IGW Attached**: `aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(InternetGateways)' --output text | grep -q '^1$'`
- **NAT Gateway**: `aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(NatGateways)' --output text | grep -q '^1$'`
- **Route Tables**: `aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) --query 'length(RouteTables)' --output text | grep -q '^3$'`
