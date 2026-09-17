# Technical Quality Checklist: cert-manager K8s 1.28 Version Skew Fix

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-16
**Feature**: [cert-manager K8s 1.28 Version Skew Fix](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the replacement pin exact (`v1.19.4`) with the static manifest URL explicit?
- [x] CHK002 Is the root cause documented with the exact API-server error (`strict decoding error: unknown field "spec.versions[0].selectableFields"`) and the version evidence (v1.20.2=4, v1.19.4=0 occurrences)?
- [x] CHK003 Is the change surface explicit (trigger `cert_manager_ref` + SSM command URL in `null_resource.apply_cert_manager`; issuers manifest unchanged)?
- [x] CHK004 Is the in-place repair path explicit (trigger change re-runs provisioner; idempotent `kubectl apply` fixes the partial v1.21.1 install without destroy/recreate)?
- [~] CHK005 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope; static manifest)

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Does the fix follow the established version-skew precedent (`004-3-ebs-csi-k8s-version-skew`: addon version must match cluster minor)?
- [x] CHK007 Is the `instance_id` trigger preserved (004-10 recreation pattern) so the fix also applies to future cluster recreations?
- [x] CHK008 Is the apply idempotent and version-controlled (re-runnable `null_resource`, re-triggers only on pinned-version change)?
- [x] CHK009 Are the SSM apply mechanics unchanged (bootstrap-instance-id gate, send-command, poll loop)?
- [x] CHK010 Is the dependency on `004-app-infrastructure` preserved (`depends_on = [null_resource.apply_app_infrastructure]`)?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (6 CRDs, 2 ClusterIssuers, image tag `v1.19.4`, plan delta = 1 null_resource)?
- [x] CHK013 Is the AC ordering explicit (CRDs → pods Ready → ClusterIssuers → image tag)?
- [x] CHK014 Does AC-002 bound the Terraform plan delta to the single `null_resource` replacement (no collateral changes)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Follow-on fix to `004-1-cert-manager` (next sequential number per project convention; `004-1` files are not edited).
- `letsencrypt-prod` issuance still requires a live domain (Route 53 work); this spec only makes the install succeed on K8s 1.28.
