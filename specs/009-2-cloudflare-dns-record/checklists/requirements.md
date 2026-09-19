# Requirements Checklist: Cloudflare DNS Record (replace Route 53)

## Technical Contracts Declared
- [x] Terraform HCL contract: `node_route53` deletion + `apply_route53_record` → `apply_cloudflare_record` rename (exact HCL)
- [x] SSM script contract: `create-cloudflare-record.sh` full content (token from SSM, ALB DNS poll, zone lookup, CNAME upsert)
- [x] Kubernetes manifest contract: none (no manifest change)
- [x] Data & storage: SSM SecureString `/sdd-k8s-platform/secrets/cloudflare-api-token` (user-created, one-time)
- [x] Network & security: `node_route53` deleted; no new IAM (node_ssm_parameters covers the token path); egress proven; Route 53 zone cleanup noted

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — policy deletion + resource rename only
- [x] AC-003: Cloudflare CNAME present, pointing at the ALB, `proxied=false`
- [x] AC-004: Certificate `Ready=True` (Let's Encrypt)
- [x] AC-005: `letsencrypt-prod` issuer `READY: True`
- [x] AC-006: HTTPS curls return 200 (frontend + backend)

## Security, IAM & Network Boundaries
- [x] Token via SSM SecureString (project convention), NOT GitHub — token never in the SSM command document or Terraform state
- [x] No new IAM policy (node_ssm_parameters already grants ssm:GetParameter on /sdd-k8s-platform/*)
- [x] `proxied=false` documented as critical (ALB must serve the Let's Encrypt cert)
- [x] No new SG rules; egress already proven (cert-manager download)

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (143 lines)
- [x] Root cause stated as a technical fact (Cloudflare is the DNS authority; Route 53 record invisible), not narrative

## SpecKit Constraints
- [x] Follow-on numbering: `009-2` (next sequential in the 009 series)
- [x] User prerequisites explicit (Cloudflare zone + SSM token)
- [x] Testing policy: no test generation; AC-003–AC-006 user-managed SSM/CLI checks
