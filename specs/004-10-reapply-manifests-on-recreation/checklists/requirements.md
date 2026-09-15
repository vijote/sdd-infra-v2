# Technical Quality Checklist: Re-apply Cluster Manifests on Control-Plane Recreation

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-15
**Feature**: [spec.md](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Terraform variable/module interfaces: defined — `module.control_plane.control_plane_instance_id` (existing module output) added to six `triggers` maps; no new variables
- [x] CHK002 Kubernetes API versions, namespaces, resource limits: N/A — no manifest change; existing manifests re-applied unchanged
- [x] CHK003 Helm chart dependencies: N/A — raw manifests, not Helm releases
- [x] CHK004 Flannel CNI configuration: N/A — manifest unchanged; only the apply trigger changes
- [x] CHK005 NGINX Ingress Controller settings: N/A — manifest unchanged
- [x] CHK006 Database credentials / StorageClasses: N/A — manifests unchanged

## 2. Infrastructure & Security Hygiene
- [x] CHK007 IAM roles bounded to least-privilege: N/A — no IAM change
- [x] CHK008 GitHub OIDC trust: N/A — no trust change
- [x] CHK009 Security Group rules: N/A — no SG change
- [x] CHK010 TLS termination / cert-manager: N/A — no cert-manager change
- [x] CHK011 Persistent storage retention: N/A — no storage change

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Every acceptance criterion maps to an executable CLI command: AC-001..AC-007 all have exact commands + expected output
- [x] CHK013 Non-functional requirements quantified: 3 nodes Ready, DaemonSet `DESIRED=READY=AVAILABLE=3`, 6 trigger maps contain `instance_id`
- [x] CHK014 Failure recovery paths testable: AC-004/AC-005 verify the recreation recovery (nodes Ready + CNI up); AC-006/AC-007 verify downstream CCM/ELB health

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
