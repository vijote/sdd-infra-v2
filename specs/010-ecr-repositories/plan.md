# Architecture Delta: ECR Repositories (frontend + backend)

**Branch**: `010-ecr-repositories` | **Date**: 2026-09-19 | **Spec**: [specs/010-ecr-repositories/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/ecr/variables.tf` | Create | `repository_names` (list(string)) input |
| `terraform/modules/ecr/main.tf` | Create | `aws_ecr_repository.this` (`for_each`), `MUTABLE` tags, `scan_on_push = true`, no lifecycle |
| `terraform/modules/ecr/outputs.tf` | Create | `repository_arns`, `repository_urls` (maps keyed by repo name) |
| `terraform/environments/dev/main.tf` | Modify | Add `module "ecr"` call with the two repository names |
| `terraform/environments/dev/outputs.tf` | Modify | Add `ecr_frontend_repository_url`, `ecr_backend_repository_url` |

No manifest, IAM, SSM, or workflow changes. The public image baseline (`nginx:alpine`, `mysql:8.0.36`) and all existing modules are untouched.

### 1.1 Exact Edits

**Edit A** — `terraform/modules/ecr/` (new module, 3 files; full HCL in spec §1.1):
- `variables.tf`: `repository_names` — `list(string)`, no default (explicit at call site).
- `main.tf`: `resource "aws_ecr_repository" "this"` with `for_each = toset(var.repository_names)`; `image_tag_mutability = "MUTABLE"`; `image_scanning_configuration { scan_on_push = true }`. No `image_tag_immutability_enabled`, no `image_lifecycle_policy`, no `encryption_configuration` (AWS-managed default).
- `outputs.tf`: `repository_arns` + `repository_urls` as `{ for name, r in aws_ecr_repository.this : name => r.<attr> }` maps.

**Edit B** — `terraform/environments/dev/main.tf`: add the `module "ecr"` block (source `../../modules/ecr`, `repository_names = ["sdd-k8s-platform/frontend", "sdd-k8s-platform/backend"]`). Placement: after the `module "worker_nodes"` block, before the `null_resource` apply chain — ECR has no dependency on the cluster, so it needs no `depends_on` and nothing depends on it.

**Edit C** — `terraform/environments/dev/outputs.tf`: append the two outputs reading `module.ecr.repository_urls["sdd-k8s-platform/frontend" | "sdd-k8s-platform/backend"]`.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: new `module.ecr` — 2 `aws_ecr_repository` resources in `us-east-1`. No IAM, no VPC/SG interaction (ECR is a regional API service).
- **Cluster Control Plane & Core Addons**: unchanged (kubeadm, Flannel, EBS CSI, CCM).
- **Platform Services**: unchanged (cert-manager, ingress-nginx).
- **Application Workloads**: unchanged (MySQL, app deployments, Ingress) — still on the public image baseline.
- **Dependency Flow**: `module.ecr` is a leaf — no `depends_on`, no inbound edges. It applies independently of the cluster and the SSM apply chain.
- **Auth boundaries (out of scope, documented)**: push role → created in the frontend app repo (separate session); in-cluster pull secret → spec 011. Node IAM already carries `AmazonEC2ContainerRegistryReadOnly`, but kubelet does not use the node role for image pulls.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` (existing `terraform-apply.yml`, push to `main`) — creates the 2 `aws_ecr_repository` resources; every existing resource no-ops. No SSM, no cluster interaction.
2. **Stage 2 - Downstream (later sessions)**: the frontend/backend app repos consume the repository URLs (from the dev outputs) for their push role + build/push workflows; spec 011 creates the in-cluster pull secret and swaps the manifest images.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY the 2 new `aws_ecr_repository` resources; zero changes to existing resources).
- **Repository Verification** (user-managed CLI): `aws ecr describe-repositories --repository-names sdd-k8s-platform/frontend sdd-k8s-platform/backend --query 'repositories[].[repositoryName,repositoryArn,repositoryUrl,imageTagMutability,imageScanningConfiguration.scanOnPush]' --output table` → 2 rows, `MUTABLE`, `scanOnPush=True`, URLs in `us-east-1`.
- **No manifest/cluster gates**: no K8s change in this spec — no rollout, no pod, no endpoint checks.
