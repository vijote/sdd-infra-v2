# Requirements Checklist: ECR Pull Secret Guard Fix

## Technical Contracts Declared
- [x] SSM script contract: exact before/after guard edit (drop the `%%ECR_REGISTRY%%` comparison; keep `-z` empty check)
- [x] Terraform HCL contract: `script_rev = "014-guard-fix"` trigger bump on `null_resource.apply_ecr_pull_secret`
- [x] Kubernetes manifest contract: none (no manifest change)
- [x] Data & storage: none (no state migration, no SSM parameters)
- [x] Network & security: no IAM change; same SSM Run Command path as 011

## Machine-Verifiable Acceptance Criteria
- [x] AC-001: `grep -c '%%ECR_REGISTRY%%'` on the script returns `1` (only line 7)
- [x] AC-002: `grep -c 'if \[ -z "$REGISTRY" \]; then'` returns `1` (empty check retained)
- [x] AC-003: `grep -c 'script_rev   = "014-guard-fix"'` in main.tf returns `1`
- [x] AC-004: next apply re-runs the null_resource; SSM invocation reaches `Success` (CI log)
- [x] AC-005: `kubectl get secret ecr-pull-secret -n sdd-apps` → dockerconfigjson, auths key = ECR URL, username `AWS`

## Security, IAM & Network Boundaries
- [x] No new IAM roles/policies
- [x] No new GitHub vars/secrets
- [x] ECR token still minted on the control plane at runtime (never in state or the command document)

## Zero Narrative / Token Efficiency
- [x] No conversational filler or marketing language
- [x] Spec < 200 lines (75 lines)
- [x] Root cause stated as a technical fact (self-referential placeholder in guard), not narrative

## SpecKit Constraints
- [x] Sequential numbering: `014` (012 reserved for manifest swap; 013 was the diagnostic)
- [x] No external prerequisites (no manual AWS resources, no new GitHub vars)
- [x] Testing policy: no test generation; AC-004/AC-005 user-managed via CI + CLI
- [x] Downstream consumer explicit (012 manifest-swap spec consumes the now-working `ecr-pull-secret`)
