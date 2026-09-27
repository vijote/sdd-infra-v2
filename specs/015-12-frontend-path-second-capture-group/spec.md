---
name: 015-12-frontend-path-second-capture-group
description: Add the second capture group to the frontend path regex so the rewrite target is defined and stops collapsing every path to /.
date: 2026-09-26
status: Draft
---

# Spec: Frontend Path Second Capture Group (Fix Persistent Rewrite-to-/)

**Feature Branch**: `015-12-frontend-path-second-capture-group` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (no new AWS resources)
- **Kubernetes / Cluster Scope**: `app-ingress` Ingress in `sdd-apps` (existing)
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-frontend-ingress.yaml`
- **Security & CI/CD**: No IAM changes; CI apply rolls the Ingress via `apply_app_services_ingress`

### 1.1 Terraform / HCL Resource Contracts
```hcl
# No Terraform resource changes. The manifest edit flows through the existing
# always-applied null_resource.apply_app_services_ingress (015-10): bump its
# manifest_rev trigger so the SSM apply re-runs.
# main.tf: manifest_rev = "015-12-frontend-second-capture-group"  (was "015-11-frontend-path-capture")
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# terraform/environments/dev/manifests/app-frontend-ingress.yaml — frontend rule ONLY:
#   - path: /()(.*?)                  # was: /(.*) — only ONE capture group, $2 undefined
#     pathType: ImplementationSpecific
#     backend:
#       service:
#         name: app-frontend
#         port:
#           number: 80
# Rationale: rewrite-target /$2 requires capture group 2. /api(/|$)(.*) has two
# groups ($2 = rest of URL). /(.*) has only one, so $2 is empty and EVERY request
# (verified: /assets/* and fake paths) rewrites to / -> index.html as text/html.
# /()(.*?) gives $1 = "" and $2 = rest of URL -> rewrite is an identity.
# The /api(/|$)(.*) rule is UNCHANGED.
```

### 1.3 Data & Storage Contracts
- None. No storage, database, or DNS changes.

### 1.4 Network & Security Contracts
- None. No SG, CNI, or IAM changes. TLS/ACME behavior unchanged (LE rate-limit retry at 2026-09-27 01:39:59 UTC is independent).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: After CI apply: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` returns `application/javascript` (not `text/html`)
- [ ] AC-003: After CI apply: `curl -skI https://demo.vijote.dev/assets/index-Dk8xwhMS.css | grep -i content-type` returns `text/css`
- [ ] AC-004: After CI apply: `curl -sk -o /dev/null -w '%{http_code}' https://demo.vijote.dev/definitely-not-a-real-path` returns `404` (no longer rewritten to index.html)
- [ ] AC-005: After CI apply: `curl -sk https://demo.vijote.dev/api/healthz` still reaches the backend
- [ ] AC-006: `kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.spec.rules[0].http.paths[?(@.backend.service.name=="app-frontend")].path}'` returns `/()(.*?)`

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: N/A
- **IAM / Security Boundaries**: N/A
- **Storage / Backup Boundaries**: N/A
- **External Prerequisites**: None — reuses existing ingress-nginx, cert-manager TLS, Cloudflare CNAME
- **Circular Dependency Prevention**: N/A — no depends_on changes
- **Testing Policy**: No unit or E2E test generation — validation performed directly against live infrastructure using CLI tools
- **Supersedes**: 015-11's `/(.*)` path (single capture group — insufficient; $2 undefined)
- **Known Gotcha (012-6)**: annotations MUST stay in `metadata` (K8s 1.28 strict decoding) — unchanged
