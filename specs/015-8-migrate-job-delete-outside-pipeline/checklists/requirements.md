# Checklist: 015-8-migrate-job-delete-outside-pipeline

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (delete standalone before pipeline, `&&` gate semantics unchanged, trigger bump)
- [x] CHK-002: Pipeline contract declared (manifest stdin flows only to `kubectl apply -f -`; delete does not consume stdin)

## Acceptance Criteria
- [x] CHK-003: AC-001/002 executable locally (fmt -check, validate with init -backend=false)
- [x] CHK-004: AC-003/004 machine-verifiable via grep
- [x] CHK-005: AC-005 user-managed cluster validation (no `no objects passed to apply`; Job recreated → Completed → rollout success)

## Constraints
- [x] CHK-006: No tests, no narrative, no new AWS resources, spec under 200 lines
