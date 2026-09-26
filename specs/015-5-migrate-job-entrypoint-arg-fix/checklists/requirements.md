# Checklist: 015-5-migrate-job-entrypoint-arg-fix

## Technical Contracts
- [x] CHK-001: Kubernetes manifest contract declared (`command: ["migrate"]`, no entrypoint path override)
- [x] CHK-002: Terraform contract declared (`migrate_rev` trigger bump only, no new variables)

## Acceptance Criteria
- [x] CHK-003: AC-001/002 executable locally (fmt -check, validate with init -backend=false)
- [x] CHK-004: AC-003/004 machine-verifiable via grep
- [x] CHK-005: AC-005 user-managed cluster validation (Job Completed → rollout success)

## Constraints
- [x] CHK-006: No tests, no narrative, no new AWS resources, spec under 200 lines
