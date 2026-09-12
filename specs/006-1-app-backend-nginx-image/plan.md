# Architecture Delta: App Backend Image Fix (nginx:alpine)

**Branch**: `006-1-app-backend-nginx-image` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/manifests/app-backend.yaml` | Modify | 4 field changes: `image` → `nginx:alpine`, `containerPort` 8080→80, readiness+liveness `httpGet.port` 8080→80, Service `targetPort` 8080→80 (Service `port` stays 80) |
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_app_backend`: `triggers.backend_image` → `"nginx:alpine"` (re-runs the provisioner) |

No new AWS resources, no module, no `bootstrap.sh` change, no secrets.

## 2. Rollout Stages

### Stage 1: Implementation
- **T001** — Edit `manifests/app-backend.yaml` (4 field changes).
- **T002** — Edit `triggers.backend_image` in `dev/main.tf` (Depends on T001).

### Stage 2: Verification (CI / user-managed, per P5/P6)
- **T003** — Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002). Plan must show **only** the `null_resource.apply_app_backend` replacement (trigger change), zero changes to other resources.
- **T004** — SSM: `kubectl rollout status deployment/app-backend -n sdd-apps` → 2/2 Ready, 0 restarts (AC-003).
- **T005** — SSM: Service port 80 → targetPort 80 (AC-004).
- **T006** — SSM: HTTP 200 via the Service from a busybox pod (AC-005).

## 3. Key Design decisions

- **Why nginx:alpine**: minimal public image that serves HTTP on port 80 out of the box (default `nginx.conf`, no config needed). Replaces the non-HTTP `crccheck/hello-world`. Alpine keeps the pull small.
- **Port 80, not 8080**: nginx's default listen port. The Service `port` was already 80, so only `targetPort` changes — 007's Ingress `backendServicePort: 80` is unaffected.
- **Trigger-only Terraform change**: `triggers.backend_image` is the sole HCL edit. Changing it forces the `null_resource` to re-run, which re-applies the updated manifest. No structural change to the SSM local-exec.
- **In-place rolling update**: `kubectl apply` on the changed Deployment triggers a rolling update of the 2 pods (new ReplicaSet, old drained). No control-plane/node replacement, no PVC impact.
- **Probes on port 80**: `httpGet /:80` — nginx serves the default page on `/` immediately, so readiness/liveness pass without `initialDelaySeconds` tuning (kept at 5/10s as in 006).

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Plan shows changes beyond the `null_resource` | The only HCL edit is the trigger value; any other diff means an unintended edit — stop and inspect |
| `nginx:alpine` pull fails (NAT egress) | 004/005/006 already pull public images successfully; if it fails, check NAT/IGW routes (node-level) |
| Rolling update stalls (old pods not draining) | nginx has no preStop hook; default terminationGracePeriodSeconds (30s) is fine. If it stalls, check pod anti-affinity/PG (none configured) |
| AC-005 busybox pod can't reach the Service | The Service is ClusterIP in `sdd-apps`; the busybox pod runs in the same namespace — DNS `app-backend.sdd-apps.svc.cluster.local` resolves via CoreDNS (003-14 verified) |

## 5. Out of Scope
- No Ingress (007), no frontend (007), no ECR (008), no MySQL connectivity (later real-app spec).
- No new SG rules, no new IAM, no `bootstrap.sh` change, no Service `port` change.
