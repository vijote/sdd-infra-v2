# Technical Quality Checklist: Worker Nodes + CNI (3-Node Cluster)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-05
**Feature**: [Worker Nodes + CNI](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform variable types, defaults, and module input/output interfaces explicitly declared?
- [x] CHK002 Is the worker bootstrap (containerd, kubelet v1.28.0, SSM join fetch, kubeadm join) explicitly specified?
- [~] CHK003 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)
- [x] CHK004 Are the upstream inputs (vpc_id, private_subnet_ids, worker SG, instance profile, control plane ID) explicitly typed and sourced?
- [x] CHK005 Is the Flannel CNI contract (VXLAN, VNI 4096, port 4789, network 192.168.0.0/16) explicitly specified?

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Are workers in private subnets across distinct AZs with no public IP?
- [x] CHK007 Is the join command retrieved from SSM SecureString (not hardcoded in user-data)?
- [x] CHK008 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK009 Is the deployment order explicit (join → CNI → Ready → CoreDNS)?
- [~] CHK010 Are persistent storage retention/backup policies specified? — N/A (no data layer)

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (instance types, AZ placement, node counts, timeouts)?
- [x] CHK013 Is the NotReady-until-CNI behavior accounted for in the AC ordering?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
