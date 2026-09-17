# Technical Quality Checklist: Route 53 Domain + Let's Encrypt TLS

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-16
**Feature**: [Route 53 Domain + Let's Encrypt TLS](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Is the Route 53 record contract exact (A ALIAS, `demo.vijote.dev.`, `SetIdentifier demo-vijote-dev-alias`, `AliasTarget` ELB zone `Z35SXDOTRQ7X7K`, `UPSERT`)?
- [x] CHK002 Is the ALB DNS source explicit (ingress-nginx Service `status.loadBalancer.ingress[0].hostname`, polled 30x10s after CCM)?
- [x] CHK003 Is the hosted-zone lookup explicit (dynamic by name `vijote.dev`, fail fast if absent)?
- [x] CHK004 Is the Ingress `tls` block + Certificate contract exact (`secretName demo-vijote-dev-tls`, `dnsNames [%%INGRESS_HOST%%]`, `issuerRef letsencrypt-prod`)?
- [x] CHK005 Is the `ingress_host` var change explicit (`app.local` -> `demo.vijote.dev`)?
- [~] CHK006 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope)

## 2. Infrastructure & Security Hygiene
- [x] CHK007 Is the IAM policy least-privilege for the operation (`route53:ChangeResourceRecordSets`, `ListResourceRecordSets`, `GetHostedZone`) with the dev-only wildcard rationale documented (004-8 precedent)?
- [x] CHK008 Is the dependency ordering explicit (`apply_route53_record` after `apply_aws_ccm`; `apply_app_frontend_ingress` after record + cert-manager)?
- [x] CHK009 Is the `instance_id` trigger preserved (004-10 recreation pattern)?
- [x] CHK010 Is the SSM apply mechanics unchanged (bootstrap-instance-id gate, send-command, poll loop)?
- [x] CHK011 Is the user-managed prerequisite explicit (vijote.dev hosted zone must exist)?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK012 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK013 Are all contract requirements quantified (ALIAS target, cert READY=True, issuer READY=True, HTTP 200 on `/` and `/api`)?
- [x] CHK014 Is the AC ordering explicit (record -> cert -> issuer -> end-to-end HTTPS)?
- [x] CHK015 Is the no-nslookup constraint honored (AGENTS.md) — DNS+TLS+routing proven by the HTTPS curl (AC-006)?
- [x] CHK016 Does AC-002 bound the Terraform plan delta (new null_resource + new IAM policy + ingress re-apply; no unexpected diffs)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- Follow-on to `007-app-frontend-ingress` (the spec that deferred the real domain) and `004-1/004-13/004-14` (cert-manager).
- `letsencrypt-prod` flips to `READY: True` only after the first issuance (AC-005) — expected behavior, not a failure.
