# Spec: Ingress Frontend Path Capture (Fix White Page)

**Feature Branch**: `015-11-ingress-frontend-path-capture` | **Date**: 2026-09-26 | **Status**: Draft

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
# main.tf: manifest_rev = "015-11-frontend-path-capture"  (was "015-10-services-split")
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# terraform/environments/dev/manifests/app-frontend-ingress.yaml — frontend rule ONLY:
#   - path: /(.*)                      # was: / (Prefix) — no capture groups, $2 empty
#     pathType: ImplementationSpecific # was: Prefix
#     backend:
#       service:
#         name: app-frontend
#         port:
#           number: 80
# Rationale: ingress-level annotations use-regex: "true" + rewrite-target: /$2 apply
# to EVERY path. With path /(.*) the rewrite becomes an identity for non-/api paths:
# /assets/index.js -> $2 = assets/index.js -> served as-is (correct Content-Type).
# The /api(/|$)(.*) rule is UNCHANGED.
```

### 1.3 Data & Storage Contracts
- None. No storage, database, or DNS changes.

### 1.4 Network & Security Contracts
- None. No SG, CNI, or IAM changes. TLS/ACME behavior unchanged.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable:
- [ ] AC-001: `terraform fmt -check -recursive && terraform validate` passes in `terraform/environments/dev`
- [ ] AC-002: After CI apply: `curl -sI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` returns `application/javascript` (not `text/html`)
- [ ] AC-003: After CI apply: `curl -sI https://demo.vijote.dev/assets/index-Dk8xwhMS.css | grep -i content-type` returns `text/css`
- [ ] AC-004: After CI apply: `curl -s https://demo.vijote.dev/api/healthz` (or `/api/health`) still reaches the backend (non-404 from ingress; backend contract response)
- [ ] AC-005: `kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.spec.rules[0].http.paths[?(@.backend.service.name=="app-frontend")].path}'` returns `/(.*)`

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: N/A
- **IAM / Security Boundaries**: N/A
- **Storage / Backup Boundaries**: N/A
- **External Prerequisites**: None — reuses existing ingress-nginx, cert-manager TLS, Cloudflare CNAME
- **Circular Dependency Prevention**: N/A — no depends_on changes
- **Testing Policy**: No unit or E2E test generation — validation performed directly against live infrastructure using CLI tools
- **Source**: `.coda/docs/handoff-ingress-frontend-rewrite.md` (frontend agent handoff; root cause + evidence)
- **Known Gotcha (012-6)**: annotations MUST stay in `metadata` (K8s 1.28 strict decoding) — unchanged
