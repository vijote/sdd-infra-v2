# GitHub Variables & AWS Role Chaining Spec

**Purpose**: Secure credential management using GitHub repository variables and AWS role chaining to avoid circular dependencies.

## Scope
- GitHub repository variables for AWS configuration
- AWS IAM role chaining (bootstrap → assume role)
- OIDC authentication with GitHub Actions
- Dynamic region configuration
- Least-privilege security boundaries

## Key Files
- `spec.md` - Technical specification with variable contracts and role chaining patterns
- `checklists/requirements.md` - Technical quality checklist (18 checks)

## Main Components
1. **Repository Variables**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION
2. **Role Chaining**: Bootstrap role assumes target role with temporary credentials
3. **Security Boundaries**: Bootstrap role limited to sts:AssumeRole only
4. **Dynamic Configuration**: All workflows use env context for repository variables
5. **External Prerequisites**: AWS roles created via CloudFormation to avoid bootstrap paradox

## Dependencies
- Requires manual setup of repository variables in GitHub settings
- AWS roles must be pre-provisioned via CloudFormation in `cloudformation/` folder
- Depends on 000-cicd-workflows for workflow infrastructure

## Quick Reference
- **Status**: Draft
- **Acceptance Criteria**: 7 machine-verifiable criteria
- **Security Model**: Bootstrap role (minimal) → Assume role (full permissions)
- **Key Constraint**: No hardcoded regions, all configuration via repository variables
- **Testing Policy**: Validation via AWS CLI commands, no unit/E2E tests