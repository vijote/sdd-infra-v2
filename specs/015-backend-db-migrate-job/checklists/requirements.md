# Checklist: 015-backend-db-migrate-job

## Technical Contracts
- [x] CHK-001: Terraform/HCL contract declared (locals addition + `apply_app_backend` trigger/SSM sequence, no new variables)
- [x] CHK-002: Kubernetes manifest contract declared (batch/v1 Job, exact env/secretKeyRef wiring, backoffLimit 0)
- [x] CHK-003: Data/migration contract declared (DB pre-create + grants bootstrap, migrate-does-not-CREATE-DATABASE handled)
- [x] CHK-004: Security contract declared (non-root DB_USER, secret injection from mysql-secret, no plaintext)

## Machine-Verifiable Acceptance Criteria
- [x] CHK-005: All AC-001..AC-007 are executable CLI commands (terraform fmt/validate/plan, kubectl wait/get/exec/rollout)
- [x] CHK-006: Exit-code semantics explicit (Job pod exit 0 = success; non-zero -> wait timeout -> apply fails -> rollout blocked)
- [x] CHK-007: Ordering contract machine-verifiable (MySQL Ready -> bootstrap -> Job complete -> Deployment rollout)

## Boundaries & Policy
- [x] CHK-008: Network boundaries specified (in-cluster mysql ClusterIP DNS, port 3306)
- [x] CHK-009: Baseline mode defined (tag empty -> Job + bootstrap skipped)
- [x] CHK-010: Zero narrative — technical content only, spec under 200 lines (105 lines)
- [x] CHK-011: Testing policy respected (no test generation; direct AWS/cluster CLI validation only)
- [x] CHK-012: Concurrency decision recorded (single-run Job; GET_LOCK deferred)
