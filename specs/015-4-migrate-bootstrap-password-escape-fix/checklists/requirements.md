# Checklist: 015-4-migrate-bootstrap-password-escape-fix

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (single-backslash `\"` escape; `\\\"` is wrong)
- [x] CHK-002: Quoting contract declared (payload must contain plain `-p"$MYSQL_ROOT_PASSWORD"`)
- [x] CHK-003: Gate contract declared (single &&-chain preserved)
- [x] CHK-004: Security contract declared (password expands only in pod env)

## Machine-Verifiable Acceptance Criteria
- [x] CHK-005: All AC-001..AC-005 are executable CLI commands or explicit inspections
- [x] CHK-006: Root cause proven (ERROR 1045 + payload decode showing `\"` before quotes; PVC age ruled out stale volume)
- [x] CHK-007: One-line fix scope (base64encode argument only + trigger bump)

## Boundaries & Policy
- [x] CHK-008: No manifest changes; main.tf only
- [x] CHK-009: Zero narrative — technical content only, spec under 200 lines (51 lines)
- [x] CHK-010: Testing policy respected (no test generation; user-managed cluster validation)
- [x] CHK-011: Follow-on spec convention respected (015-3 untouched; new sequential 015-4)
