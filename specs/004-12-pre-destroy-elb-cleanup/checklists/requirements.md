# Technical Quality Checklist: Pre-Destroy CCM ELB Cleanup

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-16
**Feature**: [spec.md](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Terraform variable/module interfaces: N/A — no Terraform code changes (workflow-only fix)
- [x] CHK002 Kubernetes API versions, namespaces, resource limits: N/A — no cluster change
- [x] CHK003 Helm chart dependencies: N/A — no Helm
- [x] CHK004 Flannel CNI configuration: N/A — no CNI change
- [x] CHK005 NGINX Ingress Controller settings: N/A — manifest unchanged
- [x] CHK006 Database credentials / StorageClasses: N/A — no storage change
- [x] CHK007 Workflow contract: defined — new `Pre-Destroy ELB Cleanup` step in `terraform-destroy.yml` (VPC-by-tag → list Classic ELBs → delete + wait), positioned after `Terraform Init`, before `Terraform Destroy`

## 2. Infrastructure & Security Hygiene
- [x] CHK008 IAM roles bounded to least-privilege: N/A — no IAM change (assume role's `PowerUserAccess` already grants `elasticloadbalancing:*` + `ec2:Describe*`)
- [x] CHK009 GitHub OIDC trust: N/A — no trust change
- [x] CHK010 Security Group rules: N/A — no SG change (orphaned CCM ELB SG is a known non-blocking side-effect, out of scope)
- [x] CHK011 TLS termination / cert-manager: N/A
- [x] CHK012 Persistent storage retention: N/A

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK013 Every acceptance criterion maps to an executable CLI command: AC-001..AC-008 all have exact grep/actionlint commands + expected output
- [x] CHK014 Non-functional requirements quantified: step ordering (cleanup before destroy), VPC tag scoping, Classic ELB API (`aws elb`), idempotent no-op when no ELBs
- [x] CHK015 Failure recovery paths testable: AC-003/AC-004/AC-005/AC-006 verify the cleanup step's presence, ordering, VPC scoping, delete + wait behavior; AC-008 verifies no Terraform drift

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
