# GitHub Actions Role Chaining

## Overview
This spec implements native AWS role chaining for GitHub Actions workflows, replacing manual `aws sts assume-role` commands with the built-in role chaining support from `aws-actions/configure-aws-credentials@v4`.

## Problem Statement
Previous implementation required manual STS assume-role commands in GitHub Actions workflows, which:
- Added complexity and maintenance overhead
- Required manual credential extraction and environment variable management
- Increased risk of credential leakage or misconfiguration
- Made workflows harder to debug and maintain

## Solution
Implement native AWS role chaining using the `role-chaining` parameter in `aws-actions/configure-aws-credentials@v4`, which:
- Automatically handles credential extraction and session management
- Provides cleaner, more maintainable workflow configurations
- Enhances security with external ID validation
- Reduces workflow complexity and potential points of failure

## Technical Approach

### Role Chaining Architecture
```
GitHub Actions OIDC → Bootstrap Role → Assume Role → AWS Resources
                      (minimal perms)     (full perms)
```

### Key Components
1. **Bootstrap Role**: OIDC trust with GitHub Actions, minimal permissions (sts:AssumeRole only)
2. **Assume Role**: Infrastructure deployment permissions with external ID validation
3. **External ID**: Uses assume role ARN as external ID for cross-account security
4. **Session Management**: 1-hour temporary credentials auto-managed by GitHub Actions

## Prerequisites
- CloudFormation stack `github-oidc-roles` must be deployed with external ID support
- GitHub repository variables configured:
  - `AWS_BOOTSTRAP_ROLE_ARN`
  - `AWS_ASSUME_ROLE_ARN`
  - `AWS_REGION`
- GitHub Actions version: `aws-actions/configure-aws-credentials@v4` or higher

## Implementation

### Stage 1: CloudFormation Update
Add external ID condition to assume role trust policy in `cloudformation/github-oidc-roles.yaml`:

```yaml
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        AWS: BOOTSTRAP_ROLE_ARN
      Action: sts:AssumeRole
      Condition:
        StringEquals:
          sts:ExternalId: ASSUME_ROLE_ARN
```

### Stage 2-4: Workflow Migration
Replace manual assume-role steps in all GitHub Actions workflows:

**Before:**
```yaml
- name: Assume Infrastructure Role
  run: |
    CREDS=$(aws sts assume-role --role-arn ${{ env.AWS_ASSUME_ROLE_ARN }} --role-session-name github-actions)
    echo "AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)" >> $GITHUB_ENV
    echo "AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)" >> $GITHUB_ENV
    echo "AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)" >> $GITHUB_ENV
```

**After:**
```yaml
- name: Configure AWS Credentials with Role Chaining
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ env.AWS_BOOTSTRAP_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
    role-chaining: true
    role-duration-seconds: 3600
    role-session-name: github-actions
    role-external-id: ${{ env.AWS_ASSUME_ROLE_ARN }}
```

### Affected Workflows
- `.github/workflows/terraform-apply.yml`
- `.github/workflows/terraform-destroy.yml`
- `.github/workflows/terraform-unlock.yml`

## Validation

### Automated Checks
All acceptance criteria are machine-verifiable:

```bash
# Verify role chaining configuration
grep -q "role-chaining: true" .github/workflows/*.yml

# Verify external ID parameter
grep -q "role-external-id" .github/workflows/*.yml

# Verify no manual STS commands
! grep -r "aws sts assume-role" .github/workflows/

# Verify external ID condition in CloudFormation
grep -A 5 "sts:ExternalId" cloudformation/github-oidc-roles.yaml

# Verify session duration
grep -q "role-duration-seconds: 3600" .github/workflows/*.yml

# Verify env context maintained
grep -q "env:" .github/workflows/terraform-apply.yml

# Test role assumption
aws sts get-caller-identity --query Arn --output text | grep -q assume
```

### Manual Validation
1. Run any GitHub Actions workflow (e.g., terraform-apply)
2. Check workflow logs for successful role chaining
3. Verify `aws sts get-caller-identity` returns assume role ARN
4. Confirm no manual credential extraction in workflow steps

## Benefits

### Security
- **External ID Validation**: Prevents confused deputy attacks
- **Automatic Session Management**: No manual credential handling
- **Least Privilege**: Bootstrap role has minimal permissions
- **Temporary Credentials**: 1-hour session limits credential exposure

### Maintainability
- **Cleaner Workflows**: Removes complex credential extraction logic
- **Standard Pattern**: Uses GitHub Actions best practices
- **Easier Debugging**: Native tooling provides better error messages
- **Reduced Complexity**: Fewer workflow steps and potential failure points

### Operational
- **Faster Workflows**: Eliminates manual credential extraction overhead
- **Better Reliability**: Native GitHub Actions integration is more robust
- **Simplified Updates**: Single point of configuration for role chaining
- **Consistent Behavior**: All workflows use the same authentication pattern

## Files Modified
- `cloudformation/github-oidc-roles.yaml` - Added external ID condition
- `.github/workflows/terraform-apply.yml` - Replaced manual STS with role chaining
- `.github/workflows/terraform-destroy.yml` - Replaced manual STS with role chaining
- `.github/workflows/terraform-unlock.yml` - Replaced manual STS with role chaining

## Related Documentation
- [AWS IAM Role Chaining](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html)
- [GitHub Actions AWS Authentication](https://github.com/aws-actions/configure-aws-credentials)
- [Spec: GitHub Actions Role Chaining](./spec.md)
- [Plan: Architecture Delta](./plan.md)
- [Tasks: Execution Graph](./tasks.md)

## Status
✅ **Completed** - All tasks implemented and validated successfully.