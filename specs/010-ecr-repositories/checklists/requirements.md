# Requirements Checklist: ECR Repositories (frontend + backend)

## Technical Contracts Declared
- [x] Terraform HCL contract: new `terraform/modules/ecr/` (variables, `aws_ecr_repository` with `for_each`, outputs) + dev `module.ecr` call + 2 dev outputs (exact HCL)
- [x] Kubernetes manifest contract: none (public image baseline unchanged, no `imagePullSecrets`)
- [x] Data & storage: none (no SSM parameters, no secrets)
- [x] Network & security: no IAM change (push role in app repos, pull secret in spec 011); no SG rules / VPC endpoint

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — 2 new `aws_ecr_repository` only
- [x] AC-003: `aws ecr describe-repositories` returns both repos, `MUTABLE`, `scanOnPush=True`, `us-east-1`

## Security, IAM & Network Boundaries
- [x] No new IAM roles/policies in this spec (explicitly deferred: push role → app repos, pull secret → spec 011)
- [x] Default AWS-managed ECR encryption (no customer KMS)
- [x] No SG rules; egress path (NAT) already proven by public image pulls

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (115 lines)
- [x] Scope boundary stated as a technical fact (ECR repos only), not narrative

## SpecKit Constraints
- [x] Sequential numbering: `010` (next after the 009 chain)
- [x] No external prerequisites (no manual AWS resources, no SSM, no GitHub vars)
- [x] Testing policy: no test generation; AC-003 user-managed CLI check
- [x] Downstream consumers explicit (app repo sessions, spec 011)
