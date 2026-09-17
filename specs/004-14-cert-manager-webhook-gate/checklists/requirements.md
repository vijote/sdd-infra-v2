# Technical Quality Checklist: cert-manager Webhook Readiness Gate

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-16
**Feature**: [cert-manager Webhook Readiness Gate](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the root cause documented with the exact error (`failed calling webhook "webhook.cert-manager.io": ... connection refused`) and the race sequence (webhook config created in same apply as webhook Deployment; issuers applied ~1s later)?
- [x] CHK002 Is the gate explicit (`kubectl rollout status deployment/cert-manager-webhook` + `deployment/cert-manager-cainjector`, `--timeout=300s`, between the two applies)?
- [x] CHK003 Is the trigger bump explicit (`cert_manager_ref` → `v1.19.4+webhook-gate`) with the reason (command string not in null_resource state)?
- [x] CHK004 Is the change surface explicit (SSM command + trigger in `null_resource.apply_cert_manager`; manifest + issuers file unchanged)?
- [~] CHK005 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope; static manifest)

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the in-place repair path explicit (trigger bump re-runs provisioner; idempotent `kubectl apply` + rollout status; no destroy/recreate)?
- [x] CHK007 Is the `instance_id` trigger preserved (004-10 recreation pattern)?
- [x] CHK008 Is the apply idempotent and version-controlled (re-runnable `null_resource`, re-triggers only on ref/instance change)?
- [x] CHK009 Are the SSM apply mechanics unchanged (bootstrap-instance-id gate, send-command, poll loop)?
- [x] CHK010 Is the dependency on `004-app-infrastructure` preserved (`depends_on = [null_resource.apply_app_infrastructure]`)?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK011 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK012 Are all contract requirements quantified (rollout timeout 300s, 2 ClusterIssuers, READY=True, SSM Status=Success)?
- [x] CHK013 Is the AC ordering explicit (pods Ready → ClusterIssuers present → READY=True → no webhook error)?
- [x] CHK014 Does AC-002 bound the Terraform plan delta to the single `null_resource` replacement (no collateral changes)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Follow-on fix to `004-13-cert-manager-k8s-version-skew` (next sequential number per project convention; 004-1/004-13 files are not edited).
- `letsencrypt-prod` issuance still requires a live domain (Route 53 work); this spec only makes the install + issuers apply succeed.
