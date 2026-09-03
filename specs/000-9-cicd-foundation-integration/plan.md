# Architecture Delta: CI/CD Foundation Integration

**Branch**: `000-9-cicd-foundation-integration` | **Date**: 2026-09-02 | **Spec**: specs/000-9-cicd-foundation-integration/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `cloudformation/github-oidc-roles.yaml` | Modify | Split into two separate stacks to resolve circular dependency |
| `.github/workflows/terraform-apply.yml` | Modify | Add OIDC authentication and role chaining |
| `.github/workflows/terraform-destroy.yml` | Modify | Add OIDC authentication and role chaining |
| `.github/workflows/terraform-unlock.yml` | Modify | Add OIDC authentication and role chaining |
| `specs/000-9-cicd-foundation-integration/required-names.md` | Create | Documentation of required names and variables |

## 2. Architectural Boundaries & Dependency Flow

- **CloudFormation Layer**: Bootstrap role stack (no dependencies) → Assume role stack (depends on bootstrap role)
- **GitHub Configuration Layer**: Repository variables (depend on CloudFormation outputs)
- **GitHub Actions Layer**: Workflows (depend on repository variables and OIDC provider)
- **Authentication Flow**: GitHub OIDC → Bootstrap Role → Assume Role → AWS Resources
- **Shared Dependencies**: GitHub OIDC provider, AWS region, repository permissions

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Bootstrap Role Stack**: Deploy CloudFormation bootstrap role with OIDC trust relationship.
2. **Stage 2 - Assume Role Stack**: Deploy CloudFormation assume role with role chaining and external ID validation.
3. **Stage 3 - Repository Variables**: Configure GitHub repository variables with CloudFormation outputs.
4. **Stage 4 - Workflow Updates**: Update GitHub Actions workflows with OIDC authentication and role chaining.
5. **Stage 5 - Integration Validation**: Validate GitHub Actions workflow execution with OIDC authentication.

## 4. Verification Gates

- **CloudFormation Validation**: GitHub Actions workflow validates CloudFormation templates before deployment
- **Bootstrap Stack Deployment**: GitHub Actions workflow deploys stack github-oidc-bootstrap-role and verifies CREATE_COMPLETE status
- **Assume Stack Deployment**: GitHub Actions workflow deploys stack github-oidc-assume-role and verifies CREATE_COMPLETE status
- **Repository Variables**: GitHub Actions workflow can access AWS_BOOTSTRAP_ROLE_ARN, AWS_ASSUME_ROLE_ARN, AWS_REGION
- **Workflow Execution**: terraform-apply.yml workflow completes with success status
- **Role Chaining**: GitHub Actions workflow performs role chaining without errors
- **Permissions Check**: GitHub Actions workflow has id-token: write, contents: read permissions
- **Export Verification**: GitHub Actions workflow can access both CloudFormation export names