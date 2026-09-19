# Requirements Checklist: ECR Pull Secret (in-cluster)

## Technical Contracts Declared
- [x] Terraform HCL contract: `null_resource.apply_ecr_pull_secret` (full HCL — SSM pattern, triggers, `%%ECR_REGISTRY%%` replace, 41-char comment)
- [x] SSM script contract: `create-ecr-pull-secret.sh` full content (token mint, fail-fast guards, idempotent delete+create)
- [x] Kubernetes manifest contract: none (no manifest change; swap is the follow-up spec)
- [x] Data & storage: none (no SSM parameters, no Parameter Store secrets)
- [x] Network & security: no IAM change (node role already has `AmazonEC2ContainerRegistryReadOnly`); no SG rules

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — only the new `null_resource.apply_ecr_pull_secret`
- [x] AC-003: `kubectl get secret ecr-pull-secret -n sdd-apps` — type `kubernetes.io/dockerconfigjson`, auths key = ECR registry URL, username `AWS`

## Security, IAM & Network Boundaries
- [x] No new IAM (node role already covers `ecr:GetAuthorizationToken`)
- [x] ECR token never in Terraform state or the SSM command document (minted on the control plane at runtime)
- [x] Token staleness (~12h) documented with the refresh procedure
- [x] No SG rules; ECR API over NAT egress (proven path)

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (170 lines)
- [x] Scope boundary stated as a technical fact (pull secret only; swap deferred to avoid ImagePullBackOff), not narrative

## SpecKit Constraints
- [x] Sequential numbering: `011` (next after 010)
- [x] No external prerequisites (no manual AWS resources, no SSM, no GitHub vars)
- [x] Testing policy: no test generation; AC-003 user-managed CLI check
- [x] Downstream consumer explicit (012 manifest-swap spec)
