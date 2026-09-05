# Spec: Assume Role IAM Permissions

**Feature Branch**: `003-0-assume-role-iam-permissions` | **Date**: 2026-09-05 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: CloudFormation template correction only — no new AWS resources
- **Kubernetes / Cluster Scope**: None
- **Target Service**: `github-actions-assume-role` (Terraform deployment role)
- **Root Cause**: `PowerUserAccess` excludes all `iam:*` actions; 003-1 is the first spec requiring IAM writes (`iam:CreateRole`, `iam:CreateInstanceProfile`) and failed with 403 AccessDenied
- **Decision**: Wildcard `iam:*` policy (explicit user decision — Terraform role is acceptable with full IAM scope)

### 1.1 CloudFormation Contract

File: `cloudformation/assume-role.yaml`

Add one inline policy to the existing `AssumeRole` resource, alongside `TerraformStateAccess`:

```yaml
      Policies:
        - PolicyName: TerraformStateAccess
          # ... existing, unchanged ...
        - PolicyName: TerraformIamAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - iam:*
                Resource:
                  - "*"
```

- **ManagedPolicyArns**: unchanged (`PowerUserAccess`)
- **Trust policy**: unchanged (bootstrap role only)
- **No other resource changes** in the template

### 1.2 Deployment Contract

- **Method**: User-managed CloudFormation stack update (constitution principles 5 & 6 — no local AWS CLI)
- **Command (user)**: `aws cloudformation update-stack --stack-name <assume-role-stack> --template-body file://cloudformation/assume-role.yaml --capabilities CAPABILITY_NAMED_IAM`
- **Rollback**: Remove the `TerraformIamAccess` policy block and update the stack again

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD (GitHub Actions), never locally.

- [ ] AC-001: Template declares the policy (`grep -q 'PolicyName: TerraformIamAccess' cloudformation/assume-role.yaml && grep -q 'iam:\*' cloudformation/assume-role.yaml`)
- [ ] AC-002: Policy attached to the live role (`aws iam get-role-policy --role-name github-actions-assume-role --policy-name TerraformIamAccess --query 'RolePolicy.PolicyDocument.Statement[0].Action' --output text | grep -q 'iam:\*'`)
- [ ] AC-003: 003-1 IAM role now creatable — exists after re-run of apply (`aws iam get-role --role-name sdd-k8s-platform-node-role --query 'Role.Arn' --output text`)
- [ ] AC-004: Instance profile exists and references the role (`aws iam get-instance-profile --instance-profile-name sdd-k8s-platform-node-profile --query 'InstanceProfile.Roles[0].Arn' --output text | grep -q 'sdd-k8s-platform-node-role'`)

## 3. Assumptions & Constraints

- **Scope**: `iam:*` on `*` — accepted trade-off for a dev-only, single-environment, education project; the role is already reachable only via OIDC → bootstrap → role chaining
- **Ordering**: This spec MUST be deployed before re-running the 003-1 apply; the 2 security groups from the failed run are already in state, so the re-run resumes at the IAM role
- **No Terraform changes**: `terraform/modules/cluster-plumbing/` and dev wiring are unchanged by this spec
- **State**: No Terraform state impact — this is a role permission fix, not a resource change
