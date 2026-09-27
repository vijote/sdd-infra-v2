---
name: 015-14-ingress-apply-order
description: Apply the passthrough app-ingress before the app-ingress-api rewrite Ingress so the validating webhook does not reject host and path collisions with stale objects.
date: 2026-09-26
status: Draft
---

# Spec: Ingress Apply Order (Passthrough Before API)

**Feature Branch**: `015-14-ingress-apply-order` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (no new AWS resources)
- **Kubernetes / Cluster Scope**: `app-ingress-api` + `app-ingress` Ingresses in `sdd-apps` (existing, 015-13)
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-frontend-ingress.yaml`
- **Security & CI/CD**: No IAM changes; CI apply rolls both Ingresses via `apply_app_services_ingress`

### 1.1 Terraform / HCL Resource Contracts
```hcl
# No Terraform resource changes. The manifest edit flows through the existing
# always-applied null_resource.apply_app_services_ingress (015-10): bump its
# manifest_rev trigger so the SSM apply re-runs.
# main.tf: manifest_rev = "015-14-ingress-apply-order"  (was "015-13-split-ingress-objects")
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# terraform/environments/dev/manifests/app-frontend-ingress.yaml — document ORDER only:
#   1. app-ingress (passthrough, / Prefix -> app-frontend)   <- FIRST
#   2. app-ingress-api (rewrite, /api(/|$)(.*) -> backend)   <- SECOND
# Rationale: the cluster still holds the OLD app-ingress (with the /api path from
# 015-12). Applying app-ingress-api first is rejected by the ingress-nginx
# admission webhook: host + /api path "already defined in ingress sdd-apps/app-ingress".
# Applying the passthrough app-ingress first REPLACES the old object (dropping its
# /api path), so app-ingress-api then applies without conflict.
# Object CONTENTS are unchanged from 015-13 — only document order changes.
```

### 1.3 Data & Storage Contracts
- None. No storage, database, or DNS changes.

### 1.4 Network & Security Contracts
- None. No SG, CNI, or IAM changes. TLS/ACME behavior unchanged.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: After CI apply: `kubectl get ingress -n sdd-apps` shows both `app-ingress-api` and `app-ingress` (no apply failure)
- [ ] AC-003: After CI apply: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` returns `application/javascript`
- [ ] AC-004: After CI apply: `curl -sk -o /dev/null -w '%{http_code}' https://demo.vijote.dev/definitely-not-a-real-path` returns `404`
- [ ] AC-005: After CI apply: `curl -sk https://demo.vijote.dev/api/healthz` still reaches the backend

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: N/A
- **IAM / Security Boundaries**: N/A
- **Storage / Backup Boundaries**: N/A
- **External Prerequisites**: None — reuses existing ingress-nginx, cert-manager TLS, Cloudflare CNAME
- **Circular Dependency Prevention**: N/A — no depends_on changes
- **Testing Policy**: No unit or E2E test generation — validation performed directly against live infrastructure using CLI tools
- **Source**: SSM stderr — admission webhook denied app-ingress-api: host + /api path already defined in sdd-apps/app-ingress (stale 015-12 object)
- **Known Gotcha (012-6)**: annotations MUST stay in `metadata` (K8s 1.28 strict decoding) — unchanged
