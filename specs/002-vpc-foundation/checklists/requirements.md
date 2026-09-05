# Technical Quality Checklist: VPC Foundation

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-01
**Feature**: [VPC Foundation](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [~] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined for all workloads? — N/A (VPC-only phase)
- [~] CHK003 Are Helm chart dependencies, repository URLs, and `values.yaml` schema overrides fully specified? — N/A (VPC-only phase)
- [~] CHK004 Are Flannel CNI configuration (VXLAN backend, network CIDR, VNI) explicitly defined? — N/A (VPC-only phase)
- [~] CHK005 Are NGINX Ingress Controller settings (controller class, TLS termination, annotations) specified? — N/A (VPC-only phase)
- [~] CHK006 Are database credentials and StorageClasses (EBS gp3) explicitly referenced? — N/A (VPC-only phase)

## 2. Infrastructure & Security Hygiene
- [~] CHK007 Are IAM roles bounded to least-privilege policies for control-plane and worker instances? — N/A (CI/CD roles managed by CloudFormation, see `000-8-cloudformation-circular-dependency-fix`)
- [~] CHK008 Is GitHub OIDC trust relationship properly configured with correct subject and condition filters? — N/A (OIDC trust managed by CloudFormation, see `000-8-cloudformation-circular-dependency-fix`)
- [~] CHK009 Are Security Group ingress/egress rules constrained to required cluster and service CIDRs/ports? — N/A (cluster SGs deferred to `003-compute-cluster`)
- [~] CHK010 Are TLS termination and cert-manager ClusterIssuer ACME/HTTP01 challenge specs defined? — N/A (VPC-only phase)
- [~] CHK011 Are persistent storage retention policies and backup mechanisms specified? — N/A (VPC-only phase)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Does every acceptance criterion map directly to an executable CLI command or status check?
- [x] CHK013 Are all non-functional requirements quantified with exact thresholds (timeouts, replicas, CPU/memory limits)?
- [~] CHK014 Are failure recovery paths (node recreation, pod restart, health probe timeouts) testable? — N/A (no nodes/pods in VPC-only phase)

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.