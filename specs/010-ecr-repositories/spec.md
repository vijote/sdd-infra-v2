# Spec: ECR Repositories (frontend + backend)

**Feature Branch**: `010-ecr-repositories` | **Date**: 2026-09-19 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: 2 new `aws_ecr_repository` resources in a new `terraform/modules/ecr/` module; 2 new dev-environment outputs
- **Kubernetes / Cluster Scope**: none (no manifest change; public image baseline stays)
- **Target Services / Modules**: new `module.ecr` (dev environment); no existing module touched
- **Security & CI/CD**: no IAM change, no workflow change — the existing `terraform-apply.yml` (push to `main`) applies this spec

> **Why**: the frontend/backend apps will live in their own dedicated repos (not yet created), each with its own Dockerfile, and will push images to this cluster. ECR is the registry that makes that possible. This spec creates **only the repositories**; the push role (created in the frontend repo), the in-cluster pull secret (spec 011), Dockerfiles, build/push workflows, and the manifest image swap are all out of scope.

### 1.1 Terraform / HCL Resource Contracts

New module `terraform/modules/ecr/`:

```hcl
# terraform/modules/ecr/variables.tf
variable "repository_names" {
  type        = list(string)
  description = "ECR repository names (path-prefixed) to create"
}

# terraform/modules/ecr/main.tf
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE" # SHA + latest re-push (pipeline tagging strategy)

  image_scanning_configuration {
    scan_on_push = true
  }
  # No image lifecycle policy (dev project: keep all images).
  # Encryption: default AWS-managed key (no customer KMS).
}

# terraform/modules/ecr/outputs.tf
output "repository_arns" {
  value       = { for name, r in aws_ecr_repository.this : name => r.arn }
  description = "ECR repository ARNs keyed by repository name"
}

output "repository_urls" {
  value       = { for name, r in aws_ecr_repository.this : name => r.repository_url }
  description = "ECR repository URLs (registry host + path) for image references"
}
```

Dev environment `terraform/environments/dev/main.tf`:

```hcl
module "ecr" {
  source = "../../modules/ecr"

  repository_names = [
    "sdd-k8s-platform/frontend",
    "sdd-k8s-platform/backend",
  ]
}
```

Dev environment `terraform/environments/dev/outputs.tf`:

```hcl
output "ecr_frontend_repository_url" {
  value       = module.ecr.repository_urls["sdd-k8s-platform/frontend"]
  description = "ECR URL for the frontend image (consumed by the frontend app repo pipeline + spec 011 pull secret)"
}

output "ecr_backend_repository_url" {
  value       = module.ecr.repository_urls["sdd-k8s-platform/backend"]
  description = "ECR URL for the backend image (consumed by the backend app repo pipeline + spec 011 pull secret)"
}
```

- Repository URL shape: `<account_id>.dkr.ecr.<region>.amazonaws.com/sdd-k8s-platform/<app>` (region = `var.region`, `us-east-1`).
- ECR repository names support the `path/prefix` form — no separate namespace resource needed.

### 1.2 Kubernetes Manifest Contracts
- None. `app-backend.yaml`, `app-frontend-ingress.yaml`, `mysql.yaml` keep their public images (`nginx:alpine`, `mysql:8.0.36`). No `imagePullSecrets` added in this spec.

### 1.3 Data & Storage Contracts
- None (no SSM parameters, no secrets, no storage).

### 1.4 Network & Security Contracts
- **IAM**: no new roles/policies. The push role is created in the frontend app repo (separate session); the node IAM already carries `AmazonEC2ContainerRegistryReadOnly` (`cluster-plumbing/main.tf`), but kubelet does not use the node role for pulls — the in-cluster pull secret is spec 011.
- **Network**: ECR is a regional API service; no SG rules, no VPC endpoint (CI pushes over the internet; cluster pulls over NAT egress, same path as the current public images).

## 2. Technical Acceptance Criteria

AC-001/AC-002 run in the existing `terraform-apply.yml`. AC-003 is **user-managed via CLI** (P5/P6).

- [ ] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows ONLY 2 new `aws_ecr_repository` resources; zero changes to existing resources
- [ ] AC-003: both repositories exist with the expected settings
  ```bash
  aws ecr describe-repositories \
    --repository-names sdd-k8s-platform/frontend sdd-k8s-platform/backend \
    --query 'repositories[].[repositoryName,repositoryArn,repositoryUrl,imageTagMutability,imageScanningConfiguration.scanOnPush]' \
    --output table
  # -> 2 rows: sdd-k8s-platform/frontend, sdd-k8s-platform/backend
  #    MUTABLE, scanOnPush=True, URLs in us-east-1
  ```

## 3. Assumptions & Technical Constraints

- **Region**: `us-east-1` (`var.region`); ECR repositories are regional.
- **Tagging strategy (for the future pipelines)**: git SHA + `latest`; manifests will pin the SHA. Mutable tags are required for `latest` re-push.
- **IAM boundaries**: no IAM in this spec by design — push auth lives in the app repos, pull auth in spec 011.
- **External prerequisites**: none (no manual AWS resources, no SSM parameters, no GitHub vars).
- **Downstream consumers**: (1) frontend/backend app repo sessions — push role + build/push workflows reference the repository URLs from the dev outputs; (2) spec 011 — in-cluster pull secret + manifest image swap.
- **Testing Policy**: no unit or E2E test generation — validation performed directly against AWS using CLI tools; all testing is user-managed.
