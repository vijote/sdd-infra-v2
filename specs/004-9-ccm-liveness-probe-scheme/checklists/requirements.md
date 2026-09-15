# Technical Quality Checklist: CCM Liveness Probe HTTPS Scheme

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-14
**Feature**: [spec.md](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Terraform variable/module interfaces: N/A — no HCL change; manifest is read via `base64encode(file(...))` in the existing SSM provisioner
- [x] CHK002 Kubernetes API versions, namespaces, resource limits: defined — `apps/v1` Deployment in `kube-system`, existing resource limits unchanged
- [x] CHK003 Helm chart dependencies: N/A — raw manifest, not a Helm release
- [x] CHK004 Flannel CNI configuration: N/A — no CNI change
- [x] CHK005 NGINX Ingress Controller settings: N/A — Ingress Service annotation (004-4) unchanged
- [x] CHK006 Database credentials / StorageClasses: N/A — no storage change

## 2. Infrastructure & Security Hygiene
- [x] CHK007 IAM roles bounded to least-privilege: N/A — no IAM change (004-8 wildcard stays)
- [x] CHK008 GitHub OIDC trust: N/A — no trust change
- [x] CHK009 Security Group rules: N/A — no SG change
- [x] CHK010 TLS termination / cert-manager: N/A — probe uses the CCM's self-signed secure-port cert; no cert-manager involvement
- [x] CHK011 Persistent storage retention: N/A — no storage change

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Every acceptance criterion maps to an executable CLI command: AC-001..AC-006 all have exact commands + expected output
- [x] CHK013 Non-functional requirements quantified: restart-count stability window (60s), probe `periodSeconds: 20`, `initialDelaySeconds: 15`
- [x] CHK014 Failure recovery paths testable: AC-004/AC-005 verify the liveness kill loop is gone; AC-006 verifies the downstream ELB effect

## Notes
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
