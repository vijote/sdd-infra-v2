# Technical Quality Checklist: GitHub Variables & AWS Role Chaining

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-01
**Feature**: [GitHub Variables & AWS Role Chaining](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [x] CHK002 Are GitHub repository variables properly defined with env context in workflows?
- [x] CHK003 Are AWS role chaining configurations and trust relationships fully specified?
- [x] CHK004 Are bootstrap and assume role ARNs and permissions explicitly defined?
- [x] CHK005 Are repository variable names and usage patterns consistent across workflows?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Are IAM roles bounded to least-privilege policies (bootstrap role limited to sts:AssumeRole)?
- [x] CHK007 Is GitHub OIDC trust relationship properly configured with correct subject and condition filters?
- [x] CHK008 Are role chaining session durations and credential handling secure?
- [x] CHK009 Are repository variables used instead of hardcoded values?
- [x] CHK010 Are environment variable contexts properly scoped in workflows?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command or status check?
- [x] CHK012 Are all repository variables and role configurations testable via AWS CLI?
- [x] CHK013 Are role assumption and credential validation paths testable?
- [x] CHK014 Are workflow environment variable usage patterns verifiable?

## 4. Workflow-Specific Validation
- [x] CHK015 Are all repository variables properly referenced via env context?
- [x] CHK016 Are role chaining steps correctly sequenced in workflows?
- [x] CHK017 Are bootstrap and target role permissions properly separated?
- [x] CHK018 Are region configurations dynamic via repository variables?

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
- This specification requires manual setup of repository variables in GitHub settings before execution.