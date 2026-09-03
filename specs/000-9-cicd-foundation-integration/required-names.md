# Required Names for CI/CD Foundation Integration

## GitHub Repository Variables

```bash
AWS_BOOTSTRAP_ROLE_ARN=<BootstrapRole ARN from CloudFormation>
AWS_ASSUME_ROLE_ARN=<AssumeRole ARN from CloudFormation>
AWS_REGION=<Target AWS Region>
```

## CloudFormation Stack Names

```bash
github-oidc-bootstrap-role
github-oidc-assume-role
```

## IAM Role Names

```bash
github-actions-bootstrap-role
github-actions-assume-role
```

## CloudFormation Stack Outputs

### Bootstrap Stack Outputs
- `BootstrapRoleArn` - ARN of the bootstrap role
- `BootstrapRoleName` - Name of the bootstrap role

### Assume Stack Outputs  
- `AssumeRoleArn` - ARN of the assume role
- `AssumeRoleName` - Name of the assume role

## CloudFormation Export Names

```bash
github-oidc-bootstrap-role-BootstrapRoleArn
github-oidc-bootstrap-role-BootstrapRoleName
github-oidc-assume-role-AssumeRoleArn
github-oidc-assume-role-AssumeRoleName
```

## GitHub Actions Workflow References

Workflows reference these environment variables:
- `${{ env.AWS_BOOTSTRAP_ROLE_ARN }}`
- `${{ env.AWS_ASSUME_ROLE_ARN }}`
- `${{ env.AWS_REGION }}`