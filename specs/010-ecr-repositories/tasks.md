# Execution Graph (DAG): ECR Repositories (frontend + backend)

**Input**: Design documents from `/specs/010-ecr-repositories/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 5 implementation tasks + 2 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] Create `terraform/modules/ecr/variables.tf` with `variable "repository_names"` — `type = list(string)`, `description = "ECR repository names (path-prefixed) to create"`, no default (explicit at call site)
- [x] T002 [Stage 1: Terraform] Create `terraform/modules/ecr/main.tf` with `resource "aws_ecr_repository" "this"`: `for_each = toset(var.repository_names)`, `name = each.value`, `image_tag_mutability = "MUTABLE"`, `image_scanning_configuration { scan_on_push = true }`. No `image_tag_immutability_enabled`, no `image_lifecycle_policy`, no `encryption_configuration` (AWS-managed default)
- [x] T003 [Stage 1: Terraform] Create `terraform/modules/ecr/outputs.tf` with `output "repository_arns"` (`{ for name, r in aws_ecr_repository.this : name => r.arn }`) and `output "repository_urls"` (`{ for name, r in aws_ecr_repository.this : name => r.repository_url }`), each with a description
- [x] T004 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`: add `module "ecr"` block — `source = "../../modules/ecr"`, `repository_names = ["sdd-k8s-platform/frontend", "sdd-k8s-platform/backend"]`. Place after the `module "worker_nodes"` block, before the `null_resource` apply chain. No `depends_on` (ECR is a leaf — no cluster dependency) (Depends on T001, T002, T003)
- [x] T005 [Stage 1: Terraform] In `terraform/environments/dev/outputs.tf`: append `output "ecr_frontend_repository_url"` (`value = module.ecr.repository_urls["sdd-k8s-platform/frontend"]`) and `output "ecr_backend_repository_url"` (`value = module.ecr.repository_urls["sdd-k8s-platform/backend"]`), each with a description noting the downstream consumers (app repo pipelines, spec 011 pull secret) (Depends on T004)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T006 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY 2 new `aws_ecr_repository` resources (`sdd-k8s-platform/frontend`, `sdd-k8s-platform/backend`); zero changes to existing resources
- [ ] T007 [Stage 2: Verify] AC-003: `aws ecr describe-repositories --repository-names sdd-k8s-platform/frontend sdd-k8s-platform/backend --query 'repositories[].[repositoryName,repositoryArn,repositoryUrl,imageTagMutability,imageScanningConfiguration.scanOnPush]' --output table` → 2 rows, `MUTABLE`, `scanOnPush=True`, URLs in `us-east-1`
