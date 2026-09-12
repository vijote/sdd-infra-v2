# Spec: Application Frontend + Ingress

**Feature Branch**: `007-app-frontend-ingress` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources; the ingress-nginx LoadBalancer Service already exists from 004)
- **Kubernetes / Cluster Scope**: `app-frontend` Deployment (2 replicas) + ClusterIP Service + `app-ingress` Ingress in `sdd-apps`
- **Target Services / Modules**: `sdd-apps` namespace (004), ingress-nginx controller + `IngressClass: nginx` (004), `app-backend` Service (006/006-1)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (003-3/003-11 pattern); no secrets (public image, host is a non-secret var)

### 1.1 Image Contract

- **Image**: `nginx:alpine` (public Docker Hub; serves static HTTP on container port **80** out of the box). Canonical SPA/static scaffold.
- **Pull path**: node → NAT gateway → internet (egress already proven by 004/005/006). No `imagePullSecrets`.
- **Note**: both the frontend and backend scaffolds serve the same nginx default page; path-based routing (not content) is what this spec proves. Content distinction arrives with the real app (008).

### 1.2 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/variables.tf
variable "ingress_host" {
  type        = string
  description = "Ingress host (placeholder now; real Route53 domain later)"
  default     = "app.local"
}

# terraform/environments/dev/main.tf
resource "null_resource" "apply_app_frontend_ingress" {
  depends_on = [null_resource.apply_app_backend]
  triggers   = { frontend_image = "nginx:alpine", ingress_host = var.ingress_host }
  # local-exec: SSM-agent wait → bootstrap-instance-id gate (003-11) → send-command:
  #   echo "<base64 of manifest with %%INGRESS_HOST%% replaced by var.ingress_host>" | base64 -d | kubectl apply -f -
}
```
- Identical SSM structure to `apply_app_backend` (006). The only difference: the manifest is base64-encoded **after** a `replace(file(...), "%%INGRESS_HOST%%", var.ingress_host)` (the 005 `%%TOKEN%%` pattern, applied to a non-secret value).
- `ingress_host` is a Terraform variable (default `app.local`) so the real Route53 domain is a one-line change later (a follow-on spec adds the Route53 record).

### 1.3 Kubernetes Manifest Contracts

`terraform/environments/dev/manifests/app-frontend-ingress.yaml` (3 objects, namespace `sdd-apps`):
- **Deployment `app-frontend`** — image `nginx:alpine`, 2 replicas, container port 80, readiness/liveness `httpGet /:80`, resources 64Mi/128Mi, label `app: app-frontend`.
- **Service `app-frontend`** — ClusterIP, port 80 → targetPort 80, selector `app: app-frontend`.
- **Ingress `app-ingress`** — `ingressClassName: nginx`, host `%%INGRESS_HOST%%`, two prefix rules:
  - `/api` → `app-backend:80`
  - `/` → `app-frontend:80`

### 1.4 Data & Storage Contracts
- N/A (stateless).

### 1.5 Network & Security Contracts
- The Ingress is served by the existing internet-facing ingress-nginx LoadBalancer (004). No new LB, no new SG rules.
- Routing is path-based on a single host (`/api` → backend, `/` → frontend) — the "same domain" requirement.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable. AC-001–AC-002 static (existing `terraform-apply.yml` job). AC-003–AC-006 execute **on the control plane via SSM** — per P5/P6, **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Frontend Deployment rolled out (2/2 Ready)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: Ingress exists with the correct host and both path rules
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ingress app-ingress -n sdd-apps -o jsonpath='\\''{.spec.rules[0].host}{.spec.rules[0].http.paths[0].path}{.spec.rules[0].http.paths[1].path}'\\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: Ingress has an external ADDRESS (the ingress-nginx LoadBalancer IP)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ingress app-ingress -n sdd-apps -o jsonpath={.status.loadBalancer.ingress[0].ip}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-006: Path routing works — `/` and `/api/` both return HTTP 200 via the ingress controller (Host header = ingress_host)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl run http-test --rm -it --restart=Never --image=busybox:1.36 -n sdd-apps -- sh -c '"'"'wget -qO- --header=\"Host: app.local\" http://ingress-nginx-controller.ingress-nginx.svc/ >/dev/null && wget -qO- --header=\"Host: app.local\" http://ingress-nginx-controller.ingress-nginx.svc/api/ >/dev/null && echo ROUTING_OK'"'"'"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (ingress-nginx controller + `IngressClass: nginx` + LoadBalancer), `006-app-backend` / `006-1` (`app-backend` Service for the `/api` route).
- **Downstream Consumer**: `008` (ECR + real app repos) — swaps the scaffold images for real builds; the Ingress routing is unchanged.
- **Domain**: `app.local` placeholder now (no DNS). The real Route53 domain is set by changing `var.ingress_host` (a follow-on spec adds the Route53 A/ALIAS record to the ingress-nginx LoadBalancer).
- **Idempotency**: `kubectl apply` is re-runnable; the `null_resource` re-triggers when `frontend_image` or `ingress_host` changes.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
