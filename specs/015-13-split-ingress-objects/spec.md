# Spec: Split Ingress Objects (API Rewrite vs Frontend Passthrough)

**Feature Branch**: `015-13-split-ingress-objects` | **Date**: 2026-09-26 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (no new AWS resources)
- **Kubernetes / Cluster Scope**: Two Ingress objects in `sdd-apps`: `app-ingress-api` (new) + `app-ingress` (repurposed, frontend-only)
- **Target Services / Modules**: `terraform/environments/dev/manifests/app-frontend-ingress.yaml`
- **Security & CI/CD**: No IAM changes; CI apply rolls both Ingresses via `apply_app_services_ingress`

### 1.1 Terraform / HCL Resource Contracts
```hcl
# No Terraform resource changes. The manifest edit flows through the existing
# always-applied null_resource.apply_app_services_ingress (015-10): bump its
# manifest_rev trigger so the SSM apply re-runs.
# main.tf: manifest_rev = "015-13-split-ingress-objects"  (was "015-12-frontend-second-capture-group")
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
```yaml
# terraform/environments/dev/manifests/app-frontend-ingress.yaml — Ingress section becomes TWO objects:
# 1. app-ingress-api (NEW): keeps use-regex + rewrite-target /$2 annotations,
#    single path /api(/|$)(.*) -> app-backend:80. Behavior unchanged.
# 2. app-ingress (REPURPOSED): NO rewrite annotations at all, path / (Prefix)
#    -> app-frontend:80. No rewriting: assets served as-is, unknown paths 404.
#    Keeps tls block + host. Same ingressClassName: nginx.
# Precedence: nginx-ingress gives regex locations priority over prefix, so /api
# still routes to the backend even though app-ingress matches /.
# Both objects share the same host %%INGRESS_HOST%% and tls secretName.
# Service + Certificate sections UNCHANGED.
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
- [ ] AC-004: After CI apply: `curl -sk -o /dev/null -w '%{http_code}' https://demo.vijote.dev/definitely-not-a-real-path` returns `404`
- [ ] AC-005: After CI apply: `curl -sk https://demo.vijote.dev/api/healthz` still reaches the backend
- [ ] AC-006: `kubectl get ingress -n sdd-apps` shows both `app-ingress-api` and `app-ingress`; `app-ingress` has NO `rewrite-target` annotation

## 3. Assumptions & Technical Constraints
- **Network CIDRs**: N/A
- **IAM / Security Boundaries**: N/A
- **Storage / Backup Boundaries**: N/A
- **External Prerequisites**: None — reuses existing ingress-nginx, cert-manager TLS, Cloudflare CNAME
- **Circular Dependency Prevention**: N/A — no depends_on changes
- **Testing Policy**: No unit or E2E test generation — validation performed directly against live infrastructure using CLI tools
- **Supersedes**: 015-11 (`/(.*)`) and 015-12 (`/()(.*?)`) single-ingress regex attempts — `(.*?)` is non-greedy (matches empty), so `$2` captured "" and everything still rewrote to `/`
- **Known Gotcha (012-6)**: annotations MUST stay in `metadata` (K8s 1.28 strict decoding) — unchanged
