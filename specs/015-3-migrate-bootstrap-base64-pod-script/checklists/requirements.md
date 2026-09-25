# Checklist: 015-3-migrate-bootstrap-base64-pod-script

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (base64-wrapped pod script via single base64encode call, trigger bump)
- [x] CHK-002: Quoting contract declared (control plane sees quote-free base64 only; pod bash parses SQL + password ref)
- [x] CHK-003: Gate contract declared (single &&-chained commands[] entry preserved from 015-2)
- [x] CHK-004: Security contract declared (password expands only in pod env; heredoc <<'SQL' quoted delimiter)

## Machine-Verifiable Acceptance Criteria
- [x] CHK-005: All AC-001..AC-006 are executable CLI commands or explicit inspections
- [x] CHK-006: Root cause proven from actual error (`MYSQL_ROOT_PASSWORD: unbound variable` on control plane under set -u)
- [x] CHK-007: All three prior failure modes addressed (015 -e nesting, 015-2 transit mangling, unbound variable)

## Boundaries & Policy
- [x] CHK-008: No manifest changes; main.tf only
- [x] CHK-009: Zero narrative — technical content only, spec under 200 lines (62 lines)
- [x] CHK-010: Testing policy respected (no test generation; user-managed cluster validation)
- [x] CHK-011: Follow-on spec convention respected (015/015-2 untouched; new sequential 015-3)
