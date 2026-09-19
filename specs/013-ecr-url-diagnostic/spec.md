# Spec: ECR URL Diagnostic Workflow

**Feature Branch**: `013-ecr-url-diagnostic` | **Date**: 2026-09-19 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no AWS resources created/modified; read-only `terraform output` against existing S3 state)
- **Kubernetes / Cluster Scope**: none
- **Target Services / Modules**: new GitHub Actions workflow `.github/workflows/terraform-output-diag.yml` (manual dispatch only)
- **Security & CI/CD**: reuses the existing two-tier OIDC role chain (bootstrap → `AWS_TERRAFORM_ROLE`) and `production` environment, identical to `terraform-apply.yml`

> **Why**: 011's `apply_ecr_pull_secret` fails in CI with `ERROR: REGISTRY not substituted` (guard at `create-ecr-pull-secret.sh:9`). The substitution source is `module.ecr.repository_urls["sdd-k8s-platform/frontend"]`. The apply log never prints the value (ECR repos are unchanged → no diff lines). This workflow prints `ecr_frontend_repository_url` / `ecr_backend_repository_url` from state in the same runner, confirming or refuting the empty-state-URL hypothesis.

### 1.1 GitHub Actions Workflow Contract

New `.github/workflows/terraform-output-diag.yml`:

```yaml
name: Terraform Output Diagnostics (one-off)

env:
  AWS_REGION: ${{ vars.AWS_REGION }}
  AWS_BOOTSTRAP_ROLE_ARN: ${{ vars.AWS_BOOTSTRAP_ROLE_ARN }}
  AWS_TERRAFORM_ROLE: ${{ vars.AWS_TERRAFORM_ROLE }}
  TF_VAR_state_bucket_name: ${{ vars.AWS_STATE_BUCKET_NAME }}

on:
  workflow_dispatch:          # manual only — never on push/PR

permissions:
  id-token: write
  contents: read

jobs:
  output:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v4
        with:
          terraform_version: ">=1.5.0"
      - uses: aws-actions/configure-aws-credentials@v6   # bootstrap role
        with:
          role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: aws-actions/configure-aws-credentials@v6   # target role (chained)
        with:
          role-to-assume: ${{ env.AWS_TERRAFORM_ROLE }}
          aws-region: ${{ env.AWS_REGION }}
          role-chaining: true
      - name: Terraform Output (ECR URLs)
        run: |
          cd terraform/environments/dev
          terraform init \
            -backend-config="bucket=${{ env.TF_VAR_state_bucket_name }}" \
            -backend-config="region=${{ env.AWS_REGION }}"
          echo "=== ecr_frontend_repository_url ==="
          terraform output ecr_frontend_repository_url
          echo "=== ecr_backend_repository_url ==="
          terraform output ecr_backend_repository_url
        env:
          TF_VAR_state_bucket_name: ${{ env.TF_VAR_state_bucket_name }}
          TF_VAR_region: ${{ env.AWS_REGION }}
```

- Trigger: `workflow_dispatch` only — no `push`/`pull_request` triggers, so it cannot run in the automated pipeline.
- `terraform init` with the same backend config as `terraform-apply.yml`; `terraform output` reads state only (no plan, no apply, no drift writes).
- No new GitHub vars/secrets; all four vars already exist.

### 1.2 Terraform / HCL Resource Contracts

No Terraform changes. Consumes existing 010 outputs in `terraform/environments/dev/outputs.tf`:

```hcl
output "ecr_frontend_repository_url" { value = module.ecr.repository_urls["sdd-k8s-platform/frontend"] }
output "ecr_backend_repository_url"  { value = module.ecr.repository_urls["sdd-k8s-platform/backend"] }
```

### 1.3 Data & Storage Contracts

- **State**: read-only access to S3 state bucket `sdd-k8s-platform-terraform-state` (via `TF_VAR_state_bucket_name`); no state mutation.

### 1.4 Network & Security Contracts

- **IAM**: assumes `AWS_BOOTSTRAP_ROLE_ARN` via OIDC, then chains to `AWS_TERRAFORM_ROLE` (same as apply workflow). No new IAM resources.
- **Secrets**: none.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: Workflow file exists and parses as valid YAML (`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/terraform-output-diag.yml'))"`)
- [ ] AC-002: Workflow has no `push` or `pull_request` trigger (`grep -cE '^  (push|pull_request):' .github/workflows/terraform-output-diag.yml` returns `0`)
- [ ] AC-003: Workflow uses the two-tier role chain (`grep -c 'role-chaining: true' .github/workflows/terraform-output-diag.yml` returns `1`)
- [ ] AC-004: Manual dispatch of the workflow completes with exit code 0 and prints both `ecr_frontend_repository_url` and `ecr_backend_repository_url` values (GitHub Actions run log)
- [ ] AC-005: Diagnostic verdict recorded: printed values are either (a) real `*.dkr.ecr.*.amazonaws.com` URLs → substitution path broken, or (b) empty → state refresh required; verdict drives the next follow-on spec

## 3. Assumptions & Technical Constraints

- **Existing vars**: `AWS_REGION`, `AWS_BOOTSTRAP_ROLE_ARN`, `AWS_TERRAFORM_ROLE`, `AWS_STATE_BUCKET_NAME` already configured in the GitHub repo (used by `terraform-apply.yml`).
- **State bucket**: `sdd-k8s-platform-terraform-state` (hardcoded in workflows via var).
- **Read-only guarantee**: `terraform output` performs no plan/apply; the workflow cannot mutate infrastructure or state.
- **Numbering**: `012` is reserved for the manifest image swap; this spec takes `013`.
- **Testing Policy**: No unit or E2E test generation — validation performed directly against AWS infrastructure using CLI tools.
