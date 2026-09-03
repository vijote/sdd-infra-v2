# Spec: CI/CD Workflows

**Feature Branch**: `000-0-cicd-workflows` | **Date**: 2026-09-01 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: GitHub Actions Workflows / OIDC Authentication / Job Dependencies
- **Kubernetes / Cluster Scope**: Terraform orchestration for all phases
- **Target Services / Modules**: Complete infrastructure deployment in single workflow
- **Security & CI/CD**: GitHub OIDC for AWS, state locking, approval gates

### 1.1 Terraform / HCL Resource Contracts
```hcl
variable "github_oidc_role_arn" {
  type        = string
  description = "GitHub Actions OIDC role ARN"
}
variable "state_bucket_name" {
  type        = string
  description = "S3 bucket for Terraform state"
  default     = "sdd-k8s-platform-terraform-state"
}
```

### 1.2 GitHub Actions Workflow Contracts
```yaml
# .github/workflows/terraform-apply.yml
name: Terraform Apply - Full Infrastructure
on:
  push:
    branches: [main]
    paths: ['specs/**', 'src/**']
  workflow_dispatch:
    inputs:
      phase: {default: 'all', type: choice, options: [all, phase1, phase2, phase3, phase4, phase5]}
permissions: {id-token: write, contents: read, pull-requests: write}
jobs:
  validate:
    runs-on: ubuntu-latest
    outputs: {phases: ${{ steps.plan.outputs.phases }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v4
        with: {terraform_version: ">=1.5.0"}
      - run: terraform fmt -check -recursive
      - run: terraform init
        env: {TF_VAR_region: us-east-1}
      - run: terraform validate
      - id: plan
        run: |
          terraform plan -out=tfplan -json > plan.json
          echo "phases=$(jq -r '.configuration.root_module.resources | map(.mode) | unique | join(",")' plan.json)" >> $GITHUB_OUTPUT
      - uses: actions/upload-artifact@v4
        with: {name: terraform-plan, path: tfplan, retention-days: 7}
  apply:
    needs: validate
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v4
        with: {terraform_version: ">=1.5.0"}
      - uses: aws-actions/configure-aws-credentials@v4
        with: {role-to-assume: ${{ secrets.AWS_ROLE_ARN }}, aws-region: us-east-1}
      - uses: actions/download-artifact@v4
        with: {name: terraform-plan}
      - run: terraform apply -auto-approve tfplan
        env:
          TF_VAR_region: us-east-1
          TF_VAR_github_owner: ${{ github.repository_owner }}
          TF_VAR_github_repo: ${{ github.event.repository.name }}
          TF_VAR_mysql_root_password: ${{ secrets.MYSQL_ROOT_PASSWORD }}
          TF_VAR_mysql_password: ${{ secrets.MYSQL_PASSWORD }}
      - run: |
          for phase in 001 002 003 004 005; do
            if [ -f "specs/$phase-*/validate.sh" ]; then bash "specs/$phase-*/validate.sh"; fi
          done
      - run: |
          terraform output -json > outputs.json
          echo "VPC_ID=$(terraform output -raw vpc_id)" >> $GITHUB_ENV
          echo "CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)" >> $GITHUB_ENV
          echo "APPLICATION_URL=$(terraform output -raw application_url)" >> $GITHUB_ENV
      - run: |
          echo "## 🎉 Infrastructure Deployed!" >> $GITHUB_STEP_SUMMARY
          echo "| VPC | $VPC_ID |" >> $GITHUB_STEP_SUMMARY
          echo "| Cluster | $CLUSTER_ENDPOINT |" >> $GITHUB_STEP_SUMMARY
          echo "| App | $APPLICATION_URL |" >> $GITHUB_STEP_SUMMARY

# .github/workflows/terraform-destroy.yml
name: Terraform Destroy
on:
  workflow_dispatch:
    inputs:
      confirm: {description: 'Type "destroy" to confirm', required: true}
permissions: {id-token: write, contents: read}
jobs:
  destroy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v4
        with: {terraform_version: ">=1.5.0"}
      - uses: aws-actions/configure-aws-credentials@v4
        with: {role-to-assume: ${{ secrets.AWS_ROLE_ARN }}, aws-region: us-east-1}
      - run: |
          if [ "${{ github.event.inputs.confirm }}" != "destroy" ]; then exit 1; fi
      - run: terraform init
        env: {TF_VAR_region: us-east-1}
      - run: terraform destroy -auto-approve
        env:
          TF_VAR_region: us-east-1
          TF_VAR_github_owner: ${{ github.repository_owner }}
          TF_VAR_github_repo: ${{ github.event.repository.name }}
          TF_VAR_mysql_root_password: ${{ secrets.MYSQL_ROOT_PASSWORD }}
          TF_VAR_mysql_password: ${{ secrets.MYSQL_PASSWORD }}

# .github/workflows/terraform-unlock.yml
name: Terraform State Unlock
on:
  workflow_dispatch:
    inputs:
      lock_id: {description: 'Lock ID (empty to show all)'}
permissions: {id-token: write, contents: read}
jobs:
  unlock:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v4
        with: {terraform_version: ">=1.5.0"}
      - uses: aws-actions/configure-aws-credentials@v4
        with: {role-to-assume: ${{ secrets.AWS_ROLE_ARN }}, aws-region: us-east-1}
      - run: terraform init
        env: {TF_VAR_region: us-east-1}
      - run: |
          aws dynamodb scan --table-name terraform-locks --query 'Items[0].LockID' --output text 2>/dev/null || echo "No locks"
      - run: |
          LOCK_ID="${{ github.event.inputs.lock_id }}"
          terraform force-unlock "$LOCK_ID" -force
```

### 1.3 Data & Storage Contracts
- **State Management**: Single S3 bucket with S3 native locking for all phases
- **Artifacts**: Terraform plans stored as GitHub Actions artifacts
- **Secrets**: GitHub encrypted secrets for sensitive values

### 1.4 Network & Security Contracts
- **OIDC Authentication**: GitHub Actions assume AWS role without static credentials
- **Environment Protection**: Production environment requires approval
- **State Security**: Encrypted state with access logging

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD:
- [ ] AC-001: Apply workflow triggers on main push (`git checkout main && git commit --allow-empty -m "test" && git push && sleep 60 && gh run list --workflow=terraform-apply.yml --limit=1 | grep -q "success"`)
- [ ] AC-002: All phases applied in single run (`gh run view --workflow=terraform-apply.yml --job=apply | grep -E "Phase[1-5]" | wc -l | grep -q '^5$'`)
- [ ] AC-003: State locked during apply (`aws s3api get-object-lock-configuration --bucket sdd-k8s-platform-terraform-state --key terraform.tfstate --query 'ObjectLockConfiguration.ObjectLockEnabled' --output text | grep -q "Enabled"`)
- [ ] AC-004: Destroy workflow requires confirmation (`gh workflow run terraform-destroy.yml -f confirm=not_destroy && gh run list --workflow=terraform-destroy.yml --limit=1 | grep -q "failure"`)
- [ ] AC-005: Unlock workflow releases state (`gh workflow run terraform-unlock.yml -f lock_id=$LOCK_ID && aws s3api get-object --bucket sdd-k8s-platform-terraform-state --key terraform.tfstate.lock --out /dev/null 2>/dev/null && echo $? | grep -q '^1$'`)
- [ ] AC-006: Plan artifacts stored (`gh run view --workflow=terraform-apply.yml --job=validate | grep -q "terraform-plan"`)
- [ ] AC-007: Secrets injected correctly (`gh run view --workflow=terraform-apply.yml --job=apply | grep -q "***" && echo $? | grep -q '^0$'`)

## 3. Assumptions & Technical Constraints
- **Single Apply**: All phases applied in one terraform apply from main configuration
- **State Backend**: Centralized state for all phases, no per-phase isolation
- **Job Dependencies**: Validate → Apply sequence with artifact passing
- **IAM / Security Boundaries**: GitHub OIDC role with least-privilege permissions
- **Provider Versions**: Terraform >= 1.5.0, GitHub Actions latest