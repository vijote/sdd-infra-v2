# Execution Graph (DAG): ECR URL Diagnostic Workflow

**Input**: Design documents from `/specs/013-ecr-url-diagnostic/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 2 verification gates

## Stage 1: Implementation

- [ ] T001 [Stage 1: Workflow] Create `.github/workflows/terraform-output-diag.yml` with the full YAML from spec §1.1: `name: Terraform Output Diagnostics (one-off)`; `env` block with `AWS_REGION`, `AWS_BOOTSTRAP_ROLE_ARN`, `AWS_TERRAFORM_ROLE`, `TF_VAR_state_bucket_name` (all pre-existing repo vars); `on: workflow_dispatch` ONLY (no `push`/`pull_request`); `permissions: id-token: write, contents: read`; job `output` on `ubuntu-latest` with `environment: production`; steps: checkout@v4 → setup-terraform@v4 (>=1.5.0) → configure-aws-credentials@v6 (bootstrap role) → configure-aws-credentials@v6 (target role, `role-chaining: true`) → run step: `cd terraform/environments/dev`, `terraform init -backend-config="bucket=..." -backend-config="region=..."`, then `echo` + `terraform output ecr_frontend_repository_url` and `echo` + `terraform output ecr_backend_repository_url`; run-step `env`: `TF_VAR_state_bucket_name`, `TF_VAR_region`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T002 [Stage 2: Verify] AC-001/AC-002/AC-003 static: (1) `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/terraform-output-diag.yml'))"` exits 0, (2) `grep -cE '^  (push|pull_request):' .github/workflows/terraform-output-diag.yml` returns `0`, (3) `grep -c 'role-chaining: true' .github/workflows/terraform-output-diag.yml` returns `1`
- [ ] T003 [Stage 2: Verify] AC-004/AC-005: user commits + pushes the workflow, runs "Terraform Output Diagnostics (one-off)" via workflow_dispatch; run completes exit 0 and prints both `ecr_frontend_repository_url` and `ecr_backend_repository_url`; record the verdict — (a) real `*.dkr.ecr.*.amazonaws.com` URLs → 011 substitution path broken (next: decoded SSM command), or (b) empty → state refresh of the two `aws_ecr_repository` resources (drives the fix spec)
