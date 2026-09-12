# Architecture Delta: Application Frontend + Ingress

**Branch**: `007-app-frontend-ingress` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Create | Deployment `app-frontend` (2 replicas, `nginx:alpine`, port 80, httpGet probes) + ClusterIP Service `app-frontend` (80 → 80) + Ingress `app-ingress` (host `%%INGRESS_HOST%%`, `/api` → `app-backend:80`, `/` → `app-frontend:80`), namespace `sdd-apps` |
| `terraform/environments/dev/variables.tf` | Modify | Add `variable "ingress_host"` (string, default `app.local`) |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_app_frontend_ingress` — SSM Run Command apply of the base64'd manifest (after `%%INGRESS_HOST%%` replace), mirroring `apply_app_backend` (006) |

No new AWS resources, no module, no `bootstrap.sh` change, no secrets.

## 2. Rollout Stages

### Stage 1: Implementation
- **T001** — Create `manifests/app-frontend-ingress.yaml` (Deployment + Service + Ingress).
- **T002** — Add `variable "ingress_host"` to `dev/variables.tf` (Depends on: none).
- **T003** — Add `null_resource.apply_app_frontend_ingress` to `dev/main.tf` (Depends on T001, T002).

### Stage 2: Verification (CI / user-managed, per P5/P6)
- **T004** — Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002). Plan must show **only** the new `null_resource` (1 add), zero changes to existing resources.
- **T005** — SSM: `kubectl rollout status deployment/app-frontend -n sdd-apps` → 2/2 ready (AC-003).
- **T006** — SSM: Ingress host + both path rules present (AC-004).
- **T007** — SSM: Ingress has an external ADDRESS (AC-005).
- **T008** — SSM: path routing — `/` and `/api/` both HTTP 200 via the ingress controller with `Host: app.local` (AC-006).

## 3. Key Design Decisions

- **Mirror `apply_app_backend` exactly**: same SSM-agent registration poll → bootstrap-instance-id gate (003-11) → `send-command` → status poll loop. The only differences: `depends_on = [null_resource.apply_app_backend]`, triggers `frontend_image` + `ingress_host`, and the manifest path.
- **`%%INGRESS_HOST%%` token (005 pattern, non-secret)**: the manifest contains the literal `%%INGRESS_HOST%%` in the Ingress `host:` field; Terraform does `base64encode(replace(file(".../app-frontend-ingress.yaml"), "%%INGRESS_HOST%%", var.ingress_host))`. This is the same `replace()` mechanism as 005's secrets, applied to a non-secret value — no `data "aws_ssm_parameter"` needed.
- **`ingress_host` as a Terraform var (default `app.local`)**: the real Route53 domain is a one-line change later. A follow-on spec adds the Route53 A/ALIAS record pointing at the 004 ingress-nginx LoadBalancer; 007 only needs the host string.
- **IngressClass `nginx`**: the 004 ingress-nginx controller (controller-v1.15.1) creates the default `IngressClass: nginx`; the Ingress references it by name.
- **Path routing (same domain)**: `/api` (prefix) → `app-backend:80`, `/` (prefix) → `app-frontend:80`. nginx-nginx matches the most specific prefix first, so `/api/...` hits the backend and everything else hits the frontend.
- **Service port 80 → targetPort 80**: nginx listens on 80; the Service is a 1:1 passthrough (same as 006-1's backend Service).
- **2 replicas**: proves the Deployment controller + pod scheduling across the 2 worker nodes (exercises 003-14 cross-node networking).
- **AC-006 via the ingress controller Service (not the LB IP)**: the test pod curls `ingress-nginx-controller.ingress-nginx.svc` with a `Host: app.local` header — this exercises the full Ingress routing logic (host + path matching) without depending on the external LB IP being resolvable from inside the cluster.

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Plan shows changes to existing resources | The only new objects are `variable.ingress_host` + `null_resource.apply_app_frontend_ingress`; any other diff means an unintended edit — stop and inspect |
| Ingress ADDRESS stays `<none>` (AC-005) | The 004 ingress-nginx LoadBalancer Service already has an EXTERNAL-IP (verified in 004); the Ingress inherits it. If `<none>`, check the controller Service's LB status first |
| AC-006 routing fails (404) | Verify the Ingress `host` matches the `Host` header exactly (`app.local`); verify both Services exist in `sdd-apps` with the correct selectors. The controller logs (`kubectl logs -n ingress-nginx deploy/ingress-nginx-controller`) show the matched rule |
| `%%INGRESS_HOST%%` not replaced (literal in the Ingress) | The `replace()` runs in Terraform before base64; if the literal appears in the applied Ingress, the `replace()` didn't match — check the token spelling in the manifest |
| Docker Hub pull fails (NAT egress) | 004/005/006/006-1 already pull public images successfully; if it fails, check NAT/IGW routes (node-level) |

## 5. Out of Scope
- No Route53 record (follow-on spec), no cert-manager/TLS (deferred), no ECR (008), no real app content (008).
- No new SG rules, no new IAM, no `bootstrap.sh` change, no new LoadBalancer.
