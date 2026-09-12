# Architecture Delta: Application Backend (Scaffold API)

**Branch**: `006-app-backend` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Operation | Description |
|------|-----------|-------------|
| `terraform/environments/dev/manifests/app-backend.yaml` | Create | Deployment `app-backend` (2 replicas, `crccheck/hello-world:latest`, port 8080, httpGet probes) + ClusterIP Service `app-backend` (80 → 8080), namespace `sdd-apps` |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_app_backend` — SSM Run Command apply of the base64'd manifest, mirroring `apply_mysql` (005) |

No new AWS resources, no module, no `bootstrap.sh` change, no secrets.

## 2. Rollout Stages

### Stage 1: Implementation
- **T001** — Create `manifests/app-backend.yaml` (Deployment + Service).
- **T002** — Add `null_resource.apply_app_backend` to `dev/main.tf` (Depends on T001).

### Stage 2: Verification (CI / user-managed, per P5/P6)
- **T003** — Static: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002). Plan must show **only** the new `null_resource` (1 add), zero changes to existing resources.
- **T004** — SSM: `kubectl rollout status deployment/app-backend -n sdd-apps` → 2/2 ready (AC-003).
- **T005** — SSM: Service port 80 → targetPort 8080 (AC-004).
- **T006** — SSM: pod serves HTTP 200 on 8080 (AC-005).

## 3. Key Design Decisions

- **Mirror `apply_mysql` exactly**: same SSM-agent registration poll → bootstrap-instance-id gate (003-11) → `send-command` → status poll loop. Proven pattern; no new failure modes. The only differences: `depends_on = [null_resource.apply_mysql]`, trigger `backend_image`, and the manifest path.
- **No `%%TOKEN%%` placeholders**: the scaffold has no secrets, so the manifest is base64-encoded directly (`base64encode(file(...))`) — no `replace()` chain, unlike 005.
- **Service port 80 → targetPort 8080**: the container listens on 8080; exposing 80 keeps 007's Ingress `backendServicePort: 80` clean and matches the "API on port 80" convention.
- **2 replicas**: proves the Deployment controller + pod scheduling across the 2 worker nodes (and exercises 003-14 cross-node networking between the two pods).
- **`depends_on = [apply_mysql]`**: ordering only — the scaffold does not call MySQL, but the backend is the logical next layer and 007's Ingress will route to it.
- **No `imagePullSecrets`**: public image, pulled via NAT egress (proven by 004/005 pulls).

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Docker Hub pull fails (NAT egress) | 004/005 already pull public images successfully; if it fails, check NAT/IGW routes (node-level, not pod-level) |
| Plan shows changes to existing resources | The only new object is `null_resource.apply_app_backend`; any other diff means an unintended edit — stop and inspect |
| Readiness probe flaps on `crccheck/hello-world` | The image serves `/` on 8080 immediately; `httpGet /:8080` is the correct probe. If it flaps, raise `initialDelaySeconds` |
| `wget` not in the hello-world image (AC-005) | Fallback: `kubectl exec ... deploy/app-backend -- sh -c 'cat < /dev/tcp/127.0.0.1/8080'` or use a `busybox` debug pod; AC-005 is user-managed, so the exact client is flexible |

## 5. Out of Scope
- No Ingress (007), no frontend (007), no ECR (008), no MySQL connectivity (later real-app spec).
- No new SG rules, no new IAM, no `bootstrap.sh` change.
