# Execution Graph (DAG): Application Frontend + Ingress

**Input**: Design documents from `/specs/007-app-frontend-ingress/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 3 implementation tasks + 5 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Create `terraform/environments/dev/manifests/app-frontend-ingress.yaml` — Deployment `app-frontend` (2 replicas, `nginx:alpine`, container port 80, readiness/liveness `httpGet /:80`, resources 64Mi/128Mi, label `app: app-frontend`) + ClusterIP Service `app-frontend` (port 80 → targetPort 80, selector `app: app-frontend`) + Ingress `app-ingress` (`ingressClassName: nginx`, host `%%INGRESS_HOST%%`, rules: `/api` prefix → `app-backend:80`, `/` prefix → `app-frontend:80`), namespace `sdd-apps` (Depends on: none)
- [x] T002 [Stage 1: Bootstrap] Add `variable "ingress_host"` (type string, default `app.local`, description) to `terraform/environments/dev/variables.tf` (Depends on: none)
- [x] T003 [Stage 1: Bootstrap] Add `null_resource.apply_app_frontend_ingress` to `terraform/environments/dev/main.tf` — `depends_on = [null_resource.apply_app_backend]`, `triggers = { frontend_image = "nginx:alpine", ingress_host = var.ingress_host }`, local-exec mirroring `apply_app_backend` (SSM-agent wait → bootstrap-instance-id gate → `send-command` with `echo '<base64encode(replace(file(".../app-frontend-ingress.yaml"), "%%INGRESS_HOST%%", var.ingress_host))>' | base64 -d | KUBECONFIG=... kubectl apply -f -` → status poll loop) (Depends on: T001, T002)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T004 [Stage 2: Verify] Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show only the new `variable` + `null_resource` (1 add), zero changes to existing resources (AC-001, AC-002) (Depends on: T003)
- [ ] T005 [Stage 2: Verify] SSM: `kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=300s` → 2/2 ready (AC-003) (Depends on: T004)
- [ ] T006 [Stage 2: Verify] SSM: Ingress `app-ingress` host = `app.local` + both path rules `/api` and `/` present (AC-004) (Depends on: T005)
- [ ] T007 [Stage 2: Verify] SSM: Ingress has an external ADDRESS (LoadBalancer IP, not `<none>`) (AC-005) (Depends on: T006)
- [ ] T008 [Stage 2: Verify] SSM: path routing — busybox pod `wget --header="Host: app.local"` against `ingress-nginx-controller.ingress-nginx.svc` on `/` and `/api/` both succeed (AC-006) (Depends on: T007)

## Dependencies

```
T001 ─┐
      ├→ T003 → T004 → T005 → T006 → T007 → T008
T002 ─┘
```

## Notes
- T001–T003 are the agent-executed tasks; T004–T008 run in CI / by the user (constitution P5/P6).
- The `%%INGRESS_HOST%%` token is replaced by Terraform (`replace()`) before base64 — the manifest on disk keeps the literal token.
