# Checklist: 015-9-backend-deployment-db-env

## Technical Contracts
- [x] CHK-001: Kubernetes manifest contract declared (DB env block on Deployment container, secretKeyRef mysql-secret, placeholders untouched)
- [x] CHK-002: Terraform contract declared (`manifest_rev` trigger bump only)

## Acceptance Criteria
- [x] CHK-003: AC-001/002 executable locally (fmt -check, validate with init -backend=false)
- [x] CHK-004: AC-003/004 machine-verifiable via grep
- [x] CHK-005: AC-005 user-managed cluster validation (pods Ready, rollout 2/2, no localhost dial in logs)

## Constraints
- [x] CHK-006: No tests, no narrative, no new AWS resources, spec under 200 lines
