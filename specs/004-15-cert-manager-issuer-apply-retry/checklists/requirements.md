# Requirements Checklist: cert-manager ClusterIssuer Apply Retry

## Technical Contracts Declared
- [x] Terraform HCL contract: `null_resource.apply_cert_manager` trigger bump + SSM command[1] retry loop (exact HCL + command shape)
- [x] Kubernetes manifest contract: cert-manager v1.19.4 + `cert-manager-issuers.yaml` unchanged; in-place repair via trigger bump
- [x] Data & storage: none
- [x] Network & security: unchanged (no IRSA, no new SG rules)

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `terraform fmt -check -recursive && terraform validate`
- [x] AC-002: `terraform plan -detailed-exitcode` — only `apply_cert_manager` replacement
- [x] AC-003: both ClusterIssuers present (`kubectl get clusterissuer ... | wc -l` → 2)
- [x] AC-004: both ClusterIssuers `READY: True` (jsonpath)
- [x] AC-005: SSM invocation `Status == Success` (no webhook dial error)
- [x] AC-006: webhook callable (`kubectl get clusterissuers` round-trip)

## Security, IAM & Network Boundaries
- [x] No new IAM / IRSA / SG rules; SSM Run Command pattern unchanged
- [x] No secrets on the command line (base64 manifest apply retained)

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (81 lines)
- [x] Root cause stated as a technical fact (transient webhook startup race), not narrative

## SpecKit Constraints
- [x] Follow-on numbering: `004-15` (next sequential after 004-14, the spec that owns `apply_cert_manager`)
- [x] Trigger bump documented (command string not in `null_resource` state)
- [x] Testing policy: no test generation; AC-003–AC-006 user-managed SSM checks
