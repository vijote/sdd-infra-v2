# Technical Quality Checklist: MySQL StatefulSet (In-Cluster Database)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: 005-mysql-statefulset

## Secrets Architecture (new reference pattern)
- [x] Parameter Store SecureString under `/sdd-k8s-platform/secrets/` is the single source of truth (manual one-time creation, documented commands)
- [x] Terraform consumes via `data "aws_ssm_parameter"` (read-only; PowerUserAccess already grants `ssm:GetParameter` — no CloudFormation change)
- [x] Zero new GitHub secrets/vars for 005 (minimal GitHub footprint)
- [x] Passwords never appear in the SSM command line (base64-injected into the manifest; AC-006 reads from the pod's own env)
- [x] Pattern documented as reusable for all future cluster secrets

## Infrastructure Contracts
- [x] MySQL image pinned verbatim: `mysql:8.0.36`
- [x] PVC on `ebs-gp3` (10Gi, ReadWriteOnce) via `volumeClaimTemplates` — first real EBS CSI exercise
- [x] Readiness + liveness probes defined (`mysqladmin ping`)
- [x] Service is ClusterIP only (no public exposure, no ingress)
- [x] No new AWS resources (EBS volume dynamically provisioned by the CSI driver)

## Verification (CI / user-managed, per P5/P6)
- [x] AC-001/AC-002 static: `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`
- [x] AC-003: Secret `mysql-secret` exists with all 4 keys
- [x] AC-004: PVC `mysql-data-mysql-0` phase `Bound`
- [x] AC-005: `kubectl rollout status statefulset/mysql` (readiness passing)
- [x] AC-006: authenticated `SELECT 1` via `kubectl exec` (password from pod env)

## Constraints
- [x] Spec < 200 lines
- [x] No unit/E2E tests — direct AWS CLI + SSM verification only
- [x] Manual prerequisite (SecureString params) documented and fail-fast via datasources
