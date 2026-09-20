# AGENTS.md

## Project Overview
Spec-driven infrastructure monorepo using SpecKit methodology. Infrastructure code is generated from specifications, not traditional source files. Uses Terraform, AWS, Kubernetes, and GitHub Actions with OIDC authentication.

## Agent Behavior Rules

### Bias Towards Action and Simplicity
Do not fall into long, iterative thinking loops or self-doubt. Avoid over-complicating tasks or debating multiple complex alternatives in your thoughts (e.g., going back and forth with "Wait...", "Actually...", "Alternative...").

If you find yourself:
1. Re-evaluating the same decision multiple times.
2. Trying to script or execute a highly complex workaround for a simple goal.
3. Second-guessing the simplest interpretation of the user's prompt.

**Stop immediately.** Do not proceed with a convoluted plan. Instead, pick the most straightforward and simple approach. If no simple approach is clear, ask the user for direction. It is always better to pause and ask the user than to waste time and tokens agonizing over the "perfect" solution.

## Critical Setup Requirements
- **CloudFormation first**: Must deploy `cloudformation/bootstrap-role.yaml` and `cloudformation/assume-role.yaml` before any Terraform workflows
- **No src/ directory**: Infrastructure code is generated from specs, not traditional source files
- **Role chaining**: Two-tier security model (bootstrap → assume roles) with 1-hour sessions

## Build, Test, and Lint Commands

### Terraform
```bash
terraform fmt -check -recursive  # Format validation
terraform init                    # Initialize backend
terraform validate                # Syntax validation
terraform plan -out=tfplan        # Generate execution plan
terraform apply -auto-approve     # Apply changes
terraform output -json            # Extract outputs
```

### Kubernetes
```bash
kubectl get nodes -o wide
kubectl rollout status deployment/<name>
kubectl wait --for=condition=Ready
```

### Helm
```bash
helm lint <chart-path>
helm template <release> <chart-path>
```

### Custom Validation
- Run `specs/*/validate.sh` scripts for post-deployment validation
- Scripts use `set -euo pipefail` for robust error handling
- Exit codes indicate success/failure for CI/CD integration

## Required Environment Variables

### GitHub Repository Variables
- `AWS_BOOTSTRAP_ROLE_ARN` - Bootstrap role for OIDC authentication
- `AWS_TERRAFORM_ROLE` - Infrastructure deployment role (assumed via role chaining from bootstrap)
- `AWS_REGION` - Target AWS region (default: us-east-1)
- `TF_VAR_state_bucket_name` - Terraform S3 state bucket name

### GitHub Secrets
- `MYSQL_ROOT_PASSWORD` - Database root password
- `MYSQL_PASSWORD` - Application database password

### Terraform Variables
- `TF_VAR_region` - AWS region
- `TF_VAR_github_owner` - Repository owner
- `TF_VAR_github_repo` - Repository name
- `TF_VAR_mysql_root_password` - MySQL root password
- `TF_VAR_mysql_password` - MySQL user password

## SpecKit Workflow Constraints
- **Spec size limit**: Must be under 200 lines for token efficiency
- **Task limit**: Maximum 31 tasks per feature (micro-DAG)
- **No tests allowed**: Direct AWS validation only, no unit/integration tests
- **Zero narrative policy**: Strict technical content only, no conversational filler
- **Session isolation**: Minimal context loading for LLM agents (constitution + single task)

## Automation Policies
- **No manual approvals**: Fully automated deployments on main branch push
- **Machine-verifiable criteria**: All acceptance criteria must be executable in CI/CD
- **Sequential numbering**: Features numbered 000-*, 001-*, etc.
- **Spec-driven cycle**: specify → plan → tasks → implement

## Spec File Conventions
- **Standard files**: spec.md, checklists/requirements.md (required); plan.md, tasks.md, README.md, validate.sh (optional)
- **Acceptance Criteria**: Use `AC-###` format with executable CLI commands
- **Checklist Items**: Use `CHK###` format
- **Tasks**: Use `T###` format with stage grouping
- **Metadata**: Feature branch names match spec folder names, dates in ISO format (YYYY-MM-DD)

## Infrastructure Patterns
- **Security**: OIDC authentication, role chaining, least privilege IAM policies
- **State Management**: S3 backend with DynamoDB locking, object lock configuration
- **Network**: VPC design with 10.0.0.0/16 CIDR, multi-AZ deployment
- **Modular Design**: Separate modules for networking, state backend, Kubernetes, application infrastructure

## Operational Notes
- **Terraform version**: >=1.5.0 required
- **State bucket**: `sdd-k8s-platform-terraform-state` (hardcoded in workflows)
- **Validation scripts**: Automatically run after deployment for phases 001-005
- **No network tests**: Skip nslookup checks per constitution
- **Single environment**: Dev environment only, no multi-environment setup

## Code Style Rules
- **Terraform**: Follow HCL standards, use `terraform fmt -check -recursive` for validation
- **Spec files**: Machine-verifiable acceptance criteria with exact commands
- **Infrastructure contracts**: Explicit Terraform variable definitions with types and defaults
- **Security groups**: Specific CIDRs and ports clearly defined

## Repo Etiquette
- **Branch naming**: Match spec folder names (e.g., `000-5-github-vars-aws-roles`, `001-vpc-foundation`)
- **Commit style**: Add `Co-Authored-By: CODA <coda@globant.com>` trailer as last line
- **PR conventions**: Add "Made with CODA" signature at end of PR description
- **Tagging**: Consistent `Purpose` and `ManagedBy` tags on resources

## AI Agent Guidelines
- **Project constitution**: @.specify/memory/constitution.md serves as primary AI guidelines
- **Coda skills**: 10 specialized skills in `.coda/skills/` for spec-driven development
- **SpecKit integration**: Full framework in `.specify/` with template-driven generation
- **Context loading**: Minimal context (constitution + single task) for LLM agents

## Non-Obvious Gotchas
- **No traditional package manager**: Infrastructure dependencies managed via Terraform modules
- **No traditional formatters**: Only Terraform formatting enforced
- **Spec-driven development**: Code is generated from specifications, not written directly
- **Phase dependencies**: Earlier phases provide outputs consumed by later phases
- **Cross-spec references**: Specs reference outputs from previous phases