# Spec: App Backend Image Fix (nginx:alpine)

**Feature Branch**: `006-1-app-backend-nginx-image` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources)
- **Kubernetes / Cluster Scope**: re-image the existing `app-backend` Deployment in `sdd-apps` (006) — `crccheck/hello-world:latest` → `nginx:alpine`
- **Target Services / Modules**: `app-backend` Deployment + Service (006), applied via `null_resource.apply_app_backend` (006)
- **Security & CI/CD**: unchanged — SSM Run Command apply on the control plane; public image, no secrets

### 1.1 Root Cause (why 006 is not green)

`crccheck/hello-world` is a trivial image that prints "Hello World" to stdout — it does **not** serve HTTP. The 006 manifest assumed an HTTP server on port 8080:
- `httpGet /:8080` readiness/liveness probes always fail → kubelet restarts the container (observed: 3 restarts, `0/1 Ready`)
- `wget http://127.0.0.1:8080` → connection refused (nothing bound)

The image contract in 006 was unverified. This spec replaces it with a real, minimal public HTTP server.

### 1.2 Image Contract

- **Image**: `nginx:alpine` (public Docker Hub; serves HTTP on container port **80** out of the box, default `nginx` user, no config needed).
- **Pull path**: node → NAT gateway → internet (egress already proven). No `imagePullSecrets`.
- **Port**: container port **80** (nginx default).

### 1.3 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/main.tf — null_resource.apply_app_backend (006)
triggers = {
  backend_image = "nginx:alpine"   # was "crccheck/hello-world:latest"
}
```
- Only the `triggers.backend_image` value changes — the trigger change re-runs the provisioner, which re-applies the (updated) manifest. No structural change to the resource.

### 1.4 Kubernetes Manifest Contracts

`terraform/environments/dev/manifests/app-backend.yaml` (006) — 4 field changes:
- **Deployment** `image`: `crccheck/hello-world:latest` → `nginx:alpine`
- **Deployment** `containerPort`: `8080` → `80`
- **Deployment** readiness + liveness `httpGet.port`: `8080` → `80`
- **Service** `targetPort`: `8080` → `80` (Service `port` stays `80` — so 007's Ingress `backendServicePort: 80` is unaffected)

### 1.5 Data & Storage Contracts
- N/A (stateless).

### 1.6 Network & Security Contracts
- Unchanged — ClusterIP only; no new SG rules.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable. AC-001–AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — per P5/P6, **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Deployment rolled out (2/2 replicas **Ready**, 0 restarts)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/app-backend -n sdd-apps --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: Service port 80 → targetPort 80
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc app-backend -n sdd-apps -o jsonpath='\\''{.spec.ports[0].port}{.spec.ports[0].targetPort}'\\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: Pod serves HTTP 200 on port 80 (in-cluster via the Service)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl run http-test --rm -it --restart=Never --image=busybox:1.36 -n sdd-apps -- wget -qO- http://app-backend.sdd-apps.svc.cluster.local/ | head -c 200"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `006-app-backend` (the Deployment/Service + `apply_app_backend` resource this spec re-images).
- **Downstream Consumer**: `007-app-frontend-ingress` — Ingress routes `/api` → `app-backend:80` (Service port unchanged, so 007 is unaffected by this fix).
- **Rollout**: the trigger change re-runs `apply_app_backend`; `kubectl apply` updates the Deployment in place → rolling update of the 2 pods (no control-plane/node replacement).
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
