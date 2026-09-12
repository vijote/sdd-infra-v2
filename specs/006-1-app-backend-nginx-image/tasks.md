# Execution Graph (DAG): App Backend Image Fix (nginx:alpine)

**Input**: Design documents from `/specs/006-1-app-backend-nginx-image/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Bootstrap] Edit `terraform/environments/dev/manifests/app-backend.yaml` — 4 field changes: Deployment `image` `crccheck/hello-world:latest` → `nginx:alpine`, `containerPort` 8080 → 80, readiness+liveness `httpGet.port` 8080 → 80, Service `targetPort` 8080 → 80 (Service `port` stays 80) (Depends on: none)
- [x] T002 [Stage 1: Bootstrap] Edit `terraform/environments/dev/main.tf` — `null_resource.apply_app_backend` `triggers.backend_image` `"crccheck/hello-world:latest"` → `"nginx:alpine"` (re-runs the provisioner) (Depends on: T001)

## Stage 2: Verification (CI / user-managed, per P5/P6)

- [ ] T003 [Stage 2: Verify] Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` — plan must show only the `null_resource.apply_app_backend` replacement (trigger change), zero changes to other resources (AC-001, AC-002) (Depends on: T002)
- [ ] T004 [Stage 2: Verify] SSM: `kubectl rollout status deployment/app-backend -n sdd-apps --timeout=300s` → 2/2 Ready, 0 restarts (AC-003) (Depends on: T003)
- [ ] T005 [Stage 2: Verify] SSM: Service `app-backend` port 80 → targetPort 80 (AC-004) (Depends on: T004)
- [ ] T006 [Stage 2: Verify] SSM: HTTP 200 via the Service from a busybox pod (`kubectl run http-test ... -- wget -qO- http://app-backend.sdd-apps.svc.cluster.local/`) (AC-005) (Depends on: T005)

## Dependencies

```
T001 → T002 → T003 → T004 → T005 → T006
```

## Notes
- T001–T002 are the agent-executed tasks; T003–T006 run in CI / by the user (constitution P5/P6).
- The trigger change re-runs `apply_app_backend`; `kubectl apply` performs an in-place rolling update of the 2 pods.
