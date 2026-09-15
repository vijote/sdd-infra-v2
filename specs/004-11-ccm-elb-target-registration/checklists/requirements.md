# Technical Quality Checklist: CCM ELB Target Registration (Node providerID + RBAC)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-15
**Feature**: [spec.md](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Terraform variable/module interfaces: defined — new `null_resource.set_node_provider_ids` with `instance_id` + version triggers; no new variables
- [x] CHK002 Kubernetes API versions, namespaces, resource limits: defined — CCM ClusterRole `rbac.authorization.k8s.io/v1` in `kube-system`; node `spec.providerID`
- [x] CHK003 Helm chart dependencies: N/A — raw manifests, not Helm releases
- [x] CHK004 Flannel CNI configuration: N/A — no CNI change
- [x] CHK005 NGINX Ingress Controller settings: N/A — manifest unchanged
- [x] CHK006 Database credentials / StorageClasses: N/A — no storage change

## 2. Infrastructure & Security Hygiene
- [x] CHK007 IAM roles bounded to least-privilege: N/A — no IAM change (node_aws_ccm already has ec2:Describe* + RegisterInstancesWithLoadBalancer)
- [x] CHK008 GitHub OIDC trust: N/A — no trust change
- [x] CHK009 Security Group rules: N/A — no SG change
- [x] CHK010 TLS termination / cert-manager: N/A — no cert-manager change
- [x] CHK011 Persistent storage retention: N/A — no storage change

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Every acceptance criterion maps to an executable CLI command: AC-001..AC-006 all have exact commands + expected output
- [x] CHK013 Non-functional requirements quantified: 3 nodes with `aws:///<az>/<id>` providerID, `auth can-i` = yes, ELB `Instances` non-empty
- [x] CHK014 Failure recovery paths testable: AC-003/AC-004 verify the providerID repair (in-place, no destroy); AC-002/AC-005 verify the RBAC fix; AC-006 verifies the downstream ELB effect

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
