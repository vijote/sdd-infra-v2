# Technical Quality Checklist: Operational Tooling

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-01
**Feature**: [Operational Tooling](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [ ] CHK002 Are Kubernetes API versions, CRDs, namespaces, and resource limits defined for all workloads?
- [ ] CHK003 Are Helm chart dependencies, repository URLs, and `values.yaml` schema overrides fully specified?
- [ ] CHK004 Are Flannel CNI configuration (VXLAN backend, network CIDR, VNI) explicitly defined?
- [ ] CHK005 Are NGINX Ingress Controller settings (controller class, TLS termination, annotations) specified?
- [ ] CHK006 Are database credentials and StorageClasses (EBS gp3) explicitly referenced?

## 2. Infrastructure & Security Hygiene
- [x] CHK007 Are IAM roles bounded to least-privilege policies for control-plane and worker instances?
- [x] CHK008 Is GitHub OIDC trust relationship properly configured with correct subject and condition filters?
- [x] CHK009 Are Security Group ingress/egress rules constrained to required cluster and service CIDRs/ports?
- [ ] CHK010 Are TLS termination and cert-manager ClusterIssuer ACME/HTTP01 challenge specs defined?
- [ ] CHK011 Are persistent storage retention policies and backup mechanisms specified?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Does every acceptance criterion map directly to an executable CLI command or status check?
- [x] CHK013 Are all non-functional requirements quantified with exact thresholds (timeouts, replicas, CPU/memory limits)?
- [x] CHK014 Are failure recovery paths (node recreation, pod restart, health probe timeouts) testable?

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.