# Requirements Checklist: letsencrypt-prod ACME Contact Email

## Technical Contracts Declared
- [x] Terraform HCL contract: `null_resource.apply_cert_manager` trigger bump (exact before/after)
- [x] Kubernetes manifest contract: `letsencrypt-prod` `email` value (exact before/after); `selfsigned` unchanged
- [x] Data & storage: none (account key rotated in place in the existing secret)
- [x] Network & security: unchanged; email is a public ACME contact, not a secret

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — only `apply_cert_manager` replacement
- [x] AC-003: `letsencrypt-prod` ClusterIssuer `READY: True`
- [x] AC-004: `demo-vijote-dev` Certificate `Ready=True`
- [x] AC-005: HTTPS curls return 200 (frontend + backend)

## Security, IAM & Network Boundaries
- [x] No new IAM / IRSA / SG rules; SSM Run Command pattern unchanged
- [x] Email is a public ACME contact (expiry notices) — correctly placed in the manifest, not SSM
- [x] No secrets on the command line (base64 manifest apply retained)

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (89 lines)
- [x] Root cause stated as a technical fact (LE rejects placeholder contact domains), not narrative

## SpecKit Constraints
- [x] Follow-on numbering: `004-16` (next sequential in the 004 series — the spec that owns the ClusterIssuer manifest)
- [x] Trigger bump documented (manifest base64-embedded, command string not in `null_resource` state)
- [x] Testing policy: no test generation; AC-003–AC-005 user-managed SSM checks
