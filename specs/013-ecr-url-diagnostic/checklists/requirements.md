# Requirements Checklist: ECR URL Diagnostic Workflow

## Technical Contracts Declared
- [x] GitHub Actions workflow contract: `terraform-output-diag.yml` full YAML (manual-dispatch only, two-tier role chain, `terraform output` for both ECR URL outputs)
- [x] Terraform HCL contract: none (no Terraform change; consumes existing 010 outputs `ecr_frontend_repository_url` / `ecr_backend_repository_url`)
- [x] Kubernetes manifest contract: none
- [x] Data & storage: read-only S3 state access (no mutation)
- [x] Network & security: no new IAM; reuses bootstrap → `AWS_TERRAFORM_ROLE` OIDC chain

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: workflow file parses as valid YAML (`python3 -c "import yaml,sys; yaml.safe_load(open(...))"`)
- [x] AC-002: no `push`/`pull_request` trigger (`grep -cE '^  (push|pull_request):'` returns `0`)
- [x] AC-003: two-tier role chain present (`grep -c 'role-chaining: true'` returns `1`)
- [x] AC-004: manual dispatch completes exit 0 and prints both ECR URL values (GitHub Actions log)
- [x] AC-005: diagnostic verdict recorded (real URL → substitution broken; empty → state refresh)

## Security, IAM & Network Boundaries
- [x] No new IAM roles/policies; existing role chain only
- [x] No new GitHub vars/secrets (all four vars pre-existing)
- [x] Read-only guarantee: `terraform output` performs no plan/apply
- [x] Manual-dispatch-only trigger prevents accidental pipeline runs

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (105 lines)
- [x] Scope boundary stated as a technical fact (diagnostic only; fix is a follow-on spec)

## SpecKit Constraints
- [x] Sequential numbering: `013` (012 reserved for manifest image swap)
- [x] No external prerequisites (no manual AWS resources, no new GitHub vars)
- [x] Testing policy: no test generation; AC-004/AC-005 user-managed via GitHub Actions
- [x] Downstream consumer explicit (fix spec driven by AC-005 verdict)
