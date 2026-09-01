# Anti-Patterns to Avoid in New Implementation

Based on analysis of the current codebase, here are the anti-patterns that should be avoided:

## 1. **Mixed Subnet Usage**
### Current Anti-Pattern:
```hcl
subnet_ids = [module.networking.public_subnet_id]  # Workers in public subnet!
```

### Problem:
- Worker nodes are deployed in public subnets instead of private subnets
- This exposes worker nodes to the internet and creates security risks

### Correct Pattern:
```hcl
subnet_ids = [
  module.networking.public_subnet_id,     # Control plane only
  module.networking.private_subnet_ids[0], # Workers in private
  module.networking.private_subnet_ids[1]  # Workers in private
]
```

## 2. **Hardcoded Backend Paths**
### Current Anti-Pattern:
```hcl
backend "s3" {
  key = "application-deployment/dev/terraform.tfstate"  # Hardcoded path
}
```

### Problem:
- Environment-specific paths are hardcoded in backend configuration
- Makes it difficult to reuse the same configuration across environments

### Correct Pattern:
```hcl
backend "s3" {
  key = "${path_relative_to_include()}/terraform.tfstate"  # Dynamic path
}
```

## 3. **SSH Private Key in Terraform State**
### Current Anti-Pattern:
```hcl
output "ec2_ssh_private_key" {
  value     = module.kubernetes.ssh_private_key
  sensitive = true
}
```

### Problem:
- SSH private keys stored in Terraform state (even as sensitive)
- Creates security risk if state is compromised
- Makes key rotation difficult

### Correct Pattern:
- Generate SSH keys outside Terraform
- Use AWS Key Pair service with pre-existing keys
- Or use AWS Systems Manager Session Manager instead of SSH

## 4. **Inconsistent Security Group Usage**
### Current Anti-Pattern:
```hcl
enable_ingress_sg = false  # Disabled but module exists
```

### Problem:
- Security groups are partially implemented but not used
- Creates confusion about what's actually securing the cluster

### Correct Pattern:
- Either fully implement and use all security groups
- Or remove unused security group code entirely

## 5. **Manual Provider Configuration in Modules**
### Current Anti-Pattern:
```hcl
# Providers will be configured by the calling module
# But then modules still have provider blocks
```

### Problem:
- Inconsistent provider configuration patterns
- Some modules configure providers, others expect them to be passed in

### Correct Pattern:
- Choose one pattern: either all providers configured at root or passed explicitly
- Be consistent across all modules

## 6. **Empty/Placeholder Values**
### Current Anti-Pattern:
```hcl
cluster_ca_certificate = ""  # Will be extracted from kubeconfig
```

### Problem:
- Empty values with comments about future implementation
- Creates runtime errors and unclear state

### Correct Pattern:
- Either implement the functionality properly
- Or remove the configuration entirely

## 7. **Duplicate Environment Configuration**
### Current Anti-Pattern:
- Separate dev/ and prod/ folders with nearly identical configurations
- Prod environment exists but isn't actually used

### Problem:
- Code duplication and maintenance overhead
- Unused code creates confusion

### Correct Pattern:
- Single environment with parameterized values
- Or use workspaces for environment separation

## 8. **Mixed IAM Permission Patterns**
### Current Anti-Pattern:
- EC2 instances have properly scoped permissions
- GitHub Actions has administrative permissions
- Inconsistent security posture

### Problem:
- Mixed approach to least privilege
- Some components secure, others overly permissive

### Correct Pattern:
- Apply consistent security model across all components
- Either all least privilege or all administrative (with justification)

## 9. **Hardcoded Cloud-Init Paths**
### Current Anti-Pattern:
```hcl
user_data = file("${path.module}/cloud-init/control-plane.yaml")
```

### Problem:
- File paths are hardcoded
- Makes module less flexible and harder to test

### Correct Pattern:
```hcl
user_data = templatefile("${path.module}/cloud-init/control-plane.yaml", {
  # Variables for customization
})
```

## 10. **Missing Resource Dependencies**
### Current Anti-Pattern:
```hcl
# Some resources don't explicitly declare dependencies
# Rely on implicit dependency resolution
```

### Problem:
- Race conditions during creation
- Unclear resource creation order

### Correct Pattern:
```hcl
depends_on = [
  aws_iam_role_policy_attachment.attach_k8s_ssm,
  aws_iam_role_policy_attachment.attach_ebs_csi
]
```

## 11. **Inconsistent Variable Naming**
### Current Anti-Pattern:
- Some variables use underscores: `mysql_root_password`
- Others use hyphens in resource names: `sdd-k8s-dev`

### Problem:
- Inconsistent naming conventions
- Makes code harder to read and maintain

### Correct Pattern:
- Choose one convention and stick to it
- Recommend underscores for variables, hyphens for resource names

## 12. **Missing Resource Cleanup**
### Current Anti-Pattern:
- No explicit resource deletion ordering
- No cleanup scripts for orphaned resources

### Problem:
- Resource deletion can fail due to dependencies
- Orphaned resources incur costs

### Correct Pattern:
- Implement explicit destroy ordering
- Create cleanup scripts for manual resource removal

## 13. **Overly Complex Module Structure**
### Current Anti-Pattern:
- Deep module nesting
- Some modules do very little
- Unclear separation of concerns

### Problem:
- Difficult to understand and maintain
- Over-engineering for simple tasks

### Correct Pattern:
- Flatten module structure where possible
- Each module should have a single, clear responsibility
- Combine related functionality into cohesive modules

## 14. **Missing Input Validation**
### Current Anti-Pattern:
- Variables accept any value
- No validation for required formats or ranges

### Problem:
- Runtime errors from invalid inputs
- Difficult to debug configuration issues

### Correct Pattern:
```hcl
variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  
  validation {
    condition     = can(regex("^t[23]\\.(small|medium|large)$", var.instance_type))
    error_message = "Instance type must be t2.small, t2.medium, t3.small, or t3.large."
  }
}
```

## 15. **Inconsistent Tagging Strategy**
### Current Anti-Pattern:
- Some resources have comprehensive tags
- Others have minimal or no tags
- Inconsistent tag naming

### Problem:
- Difficult to identify and manage resources
- Cost allocation challenges
- Compliance issues

### Correct Pattern:
- Implement consistent tagging strategy across all resources
- Use mandatory tags: Environment, Project, Owner, CostCenter
- Use tag policies to enforce compliance

## Summary

The main themes to avoid are:
1. **Security inconsistencies** (mixed permissions, public workers)
2. **Configuration duplication** (unused prod environment)
3. **Hardcoded values** (paths, empty placeholders)
4. **Incomplete implementations** (disabled features, missing dependencies)
5. **Naming inconsistencies** (variables vs resources)

By avoiding these anti-patterns, the new implementation will be more secure, maintainable, and consistent.