# Checklist: 015-2-migrate-bootstrap-quote-gate-fix

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (single &&-chained SSM command, trigger bump)
- [x] CHK-002: Quoting contract declared (SQL via stdin through `kubectl exec -i`; no nested single quotes)
- [x] CHK-003: Gate contract declared (one commands[] entry; failure anywhere blocks rollout)
- [x] CHK-004: Security contract declared (password expands in pod only; no plaintext in SSM command)

## Machine-Verifiable Acceptance Criteria
- [x] CHK-005: All AC-001..AC-006 are executable CLI commands or explicit inspections
- [x] CHK-006: Root cause documented from actual SSM invocation logs (exit 127, independent commands[] execution)
- [x] CHK-007: Baseline mode preserved (if/fi skips migrate, still applies Deployment)

## Boundaries & Policy
- [x] CHK-008: No manifest changes; main.tf only
- [x] CHK-009: Zero narrative — technical content only, spec under 200 lines (55 lines)
- [x] CHK-010: Testing policy respected (no test generation; user-managed cluster validation)
- [x] CHK-011: Follow-on spec convention respected (015 untouched; new sequential 015-2)
