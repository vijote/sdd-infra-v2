# Architecture Delta: GitHub Actions Role Chaining

**Branch**: `000-7-github-actions-role-chaining` | **Date**: 2026-09-02 | **Spec**: specs/000-7-github-actions-role-chaining/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `.github/workflows/terraform-apply.yml` | Modify | Replace manual STS commands with native role chaining via aws-actions/configure-aws-credentials@v4 |
| `.github/workflows/terraform-destroy.yml` | Modify | Replace manual STS commands with native role chaining via aws-actions/configure-aws-credentials@v4 |
| `.github/workflows/terraform-unlock.yml` | Modify | Replace manual STS commands with native role chaining via aws-actions/configure-aws-credentials@v4 |
| `cloudformation/github-oidc-roles.yaml` | Modify | Add external ID condition to assume role trust policy for security boundary enforcement |

## 2. Architectural Boundaries & Dependency Flow

- **GitHub Actions Layer**: Native role chaining via aws-actions/configure-aws-credentials@v4 with role-chaining=true parameter
- **Credential Flow Layer**: Bootstrap role → Assume role with external ID validation, eliminating manual credential extraction
- **Security Boundaries**: External ID condition using assume role ARN for cross-account security validation
- **Session Management**: 1-hour temporary credentials via native role chaining, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN auto-managed
- **Repository Variables Layer**: AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION maintained for env context
- **AWS IAM Layer**: Bootstrap role (OIDC trust, minimal permissions) → Assume role (infrastructure permissions, external ID validation)

## 3. Provisioning & Rollout Stages

1. **Stage 1 - CloudFormation Update**: Add external ID condition to assume role trust policy in github-oidc-roles.yaml
2. **Stage 2 - Workflow Migration**: Replace manual aws sts assume-role steps with native role chaining in terraform-apply.yml
3. **Stage 3 - Workflow Migration**: Replace manual aws sts assume-role steps with native role chaining in terraform-destroy.yml
4. **Stage 4 - Workflow Migration**: Replace manual aws sts assume-role steps with native role chaining in terraform-unlock.yml
5. **Stage 5 - Validation**: Test role chaining execution and verify assume role credentials in workflow environment

## 4. Verification Gates

- **Role Chaining Configuration**: `grep -q "role-chaining: true" .github/workflows/*.yml`
- **External ID Parameter**: `grep -q "role-external-id" .github/workflows/*.yml`
- **No Manual STS Commands**: `! grep -r "aws sts assume-role" .github/workflows/`
- **External ID Condition**: `grep -A 5 "sts:ExternalId" cloudformation/github-oidc-roles.yaml`
- **Session Duration**: `grep -q "role-duration-seconds: 3600" .github/workflows/*.yml`
- **Env Context Maintenance**: `grep -q "env:" .github/workflows/terraform-apply.yml`
- **Role Assumption**: `aws sts get-caller-identity --query Arn --output text | grep -q assume`