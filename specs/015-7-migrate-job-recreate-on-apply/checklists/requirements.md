# Checklist: 015-7-migrate-job-recreate-on-apply

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (delete-before-apply prefix in SSM command, trigger bump, no manifest changes)
- [x] CHK-002: Idempotency contract declared (`--ignore-not-found` keeps first-run and repeat-run behavior identical)

## Acceptance Criteria
- [x] CHK-003: AC-001/002 executable locally (fmt -check, validate with init -backend=false)
- [x] CHK-004: AC-003/004 machine-verifiable via grep
- [x] CHK-005: AC-005 user-managed cluster validation (Job recreated with new image → Completed → rollout success)

## Constraints
- [x] CHK-006: No tests, no narrative, no new AWS resources, spec under 200 lines
