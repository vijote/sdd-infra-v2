# Technical Quality Checklist: cert-manager + Let's Encrypt (TLS Automation)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-09
**Feature**: [cert-manager + Let's Encrypt](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the cert-manager install pinned to an exact tag (`v1.21.1`) with the static manifest URL explicit?
- [x] CHK002 Are both ClusterIssuers (`selfsigned`, `letsencrypt-prod`) explicitly specified with exact spec fields?
- [x] CHK003 Is the Let's Encrypt HTTP-01 solver contract explicit (ACME server, email, privateKeySecretRef, ingress class `nginx`)?
- [x] CHK004 Is the `null_resource.apply_cert_manager` contract explicit (triggers, provisioner interpreter, bootstrap gate, SSM send-command + poll)?
- [~] CHK005 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope; static manifest)

## 2. Infrastructure & Security Hygiene
- [x] CHK006 Is the `selfsigned` issuer the default (no DNS dependency, usable immediately for dev TLS)?
- [x] CHK007 Is the `letsencrypt-prod` issuer scoped to HTTP-01 via the nginx ingress class (no DNS-01 / Route53 scope)?
- [x] CHK008 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK009 Is the apply idempotent and version-controlled (re-runnable `null_resource`, re-triggers only on pinned-version change)?
- [x] CHK010 Is the bootstrap-instance-id gate reused (003-11) so the apply blocks until the control plane is ready?
- [x] CHK011 Is the dependency on `004-app-infrastructure` explicit (`depends_on = [null_resource.apply_app_infrastructure]`)?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK013 Are all contract requirements quantified (pinned tag, timeouts, CRD count)?
- [x] CHK014 Is the AC ordering explicit (controller ready → selfsigned issuer → letsencrypt issuer → CRDs)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- `letsencrypt-prod` requires a resolvable domain pointing at the ingress LB (configured in `005-app-deployment`); `selfsigned` works immediately.
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
