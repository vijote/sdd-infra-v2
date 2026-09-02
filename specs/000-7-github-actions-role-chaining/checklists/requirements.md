# Technical Quality Checklist: GitHub Actions Role Chaining

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-02
**Feature**: [GitHub Actions Role Chaining](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all GitHub Actions workflow contracts explicitly declared with role-chaining parameters?
- [x] CHK002 Are CloudFormation IAM role trust relationships properly specified with external ID conditions?
- [x] CHK003 Are repository variable types and usage patterns defined for all workflows?
- [x] CHK004 Are role session durations and security boundaries explicitly configured?
- [x] CHK005 Are workflow environment variables and repository variable mappings consistent?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Are IAM roles bounded to least-privilege policies with external ID validation?
- [x] CHK007 Is GitHub OIDC trust relationship properly configured with correct subject and condition filters?
- [x] CHK008 Are role chaining session durations and credential handling secure?
- [x] CHK009 Are repository variables used instead of hardcoded credentials?
- [x] CHK010 Are external ID conditions properly enforced in assume role trust policy?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command or status check?
- [x] CHK012 Are all workflow configuration patterns testable via grep and workflow execution?
- [x] CHK013 Are role assumption and credential validation paths testable?
- [x] CHK014 Are GitHub Actions role-chaining parameters verifiable?

## 4. Workflow-Specific Validation
- [x] CHK015 Are all workflows configured to use native role chaining instead of manual STS commands?
- [x] CHK016 Are role-chaining, role-external-id, and role-duration-seconds parameters properly configured?
- [x] CHK017 Are bootstrap and assume role permissions properly separated?
- [x] CHK018 Are repository variable references maintained across all workflows?

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
- This specification replaces manual AWS STS assume-role steps with native GitHub Actions role chaining.
- External ID validation provides additional security boundary for cross-account role assumption.