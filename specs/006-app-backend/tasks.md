# Execution Graph (DAG): Application Backend (Scaffold API)

**Input**: Design documents from `/specs/006-app-backend/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Create `terraform/environments/dev/manifests/app-backend.yaml` — Deployment `app-backend` (2 replicas, `crccheck/hello-world:latest`, container port 8080, readiness/liveness `httpGet /:8080`, resources 64Mi/128Mi, label `app: app-backend`) + ClusterIP Service `app-backend` (port 80 → targetPort 8080, selector `app: app-backend`), namespace `sdd-apps` (Depends on: none)
- [x] T002 [Stage 1: Bootstrap] Add `null_resource.apply_app_backend` to `terraform/environments/dev/main.tf` — `depends_on = [null_resource.apply_mysql]`, `triggers = { backend_image = "crccheck/hello-world:latest" }`, local-exec mirroring `apply_mysql` (SSM-agent wait → bootstrap-instance-id gate → `send-command` with `echo '<base64encode(file(".../app-backend.yaml"))>' | base64 -d | KUBECONFIG=... kubectl apply -f -` → status poll loop) (Depends on: T001)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T003 [Stage 2: Verify] Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show only the new `null_resource` (1 add), zero changes to existing resources (AC-001, AC-002) (Depends on: T002)
- [ ] T004 [Stage 2: Verify] SSM: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=300s` → 2/2 ready (AC-003) (Depends on: T003)
- [ ] T005 [Stage 2: Verify] SSM: Service `app-backend` port 80 → targetPort 8080 (AC-004) (Depends on: T004)
- [ ] T006 [Stage 2: Verify] SSM: pod serves HTTP 200 on 8080 (AC-005) (Depends on: T005)

## Dependencies

```
T001 → T002 → T003 → T004 → T005 → T006
```

## Notes
- T001–T002 are the agent-executed tasks; T003–T006 run in CI / by the user (constitution P5/P6).
- No `%%TOKEN%%` placeholders — the manifest is base64-encoded directly (no secrets in this spec).
