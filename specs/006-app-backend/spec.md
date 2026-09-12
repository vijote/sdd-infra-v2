# Spec: Application Backend (Scaffold API)

**Feature Branch**: `006-app-backend` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources; public image pulled from Docker Hub via NAT egress — ECR deferred to a later spec when real app repos exist)
- **Kubernetes / Cluster Scope**: `app-backend` Deployment (2 replicas) + ClusterIP Service in `sdd-apps`
- **Target Services / Modules**: `sdd-apps` namespace (004), ingress-nginx controller (004 — consumed by 007's Ingress)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (003-3/003-11 pattern); no secrets (public image, no env)

### 1.1 Image Contract

- **Image**: `crccheck/hello-world:latest` (public Docker Hub; HTTP server on container port **8080**).
- **Pull path**: node → NAT gateway → internet (egress already proven by 004/005 image pulls). No registry credentials, no `imagePullSecrets`.
- **Replacement path**: when real app repos exist, only `triggers.backend_image` + the manifest's `image:` change (ECR spec handles the registry side).

### 1.2 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/main.tf
resource "null_resource" "apply_app_backend" {
  depends_on = [null_resource.apply_mysql]
  triggers   = { backend_image = "crccheck/hello-world:latest" }
  # local-exec: SSM-agent wait → bootstrap-instance-id gate (003-11) → send-command:
  #   echo "<base64 manifest>" | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -
}
```
- Identical SSM structure to `null_resource.apply_mysql` (005): agent-registration poll, bootstrap-instance-id gate, `send-command`, status poll loop, fail-fast on `Failed`/`TimedOut`.
- No `data "aws_ssm_parameter"` datasources (no secrets in this spec).

### 1.3 Kubernetes Manifest Contracts

`terraform/environments/dev/manifests/app-backend.yaml` (2 objects, namespace `sdd-apps`):
- **Deployment `app-backend`** — image `crccheck/hello-world:latest`, 2 replicas, container port 8080, readiness probe `httpGet /:8080`, liveness probe `httpGet /:8080`, resources requests 64Mi/limits 128Mi, label `app: app-backend`.
- **Service `app-backend`** — ClusterIP, port 80 → targetPort 8080, selector `app: app-backend`. (Port 80 keeps 007's Ingress `backendServicePort` simple; internal-only.)

### 1.4 Data & Storage Contracts
- N/A (stateless scaffold; no PVC).

### 1.5 Network & Security Contracts
- ClusterIP only; no ingress in this spec (007 adds the Ingress routing `/api` → `app-backend:80`).
- No new SG rules (pod traffic stays within the node SGs; 003-14 VXLAN rules already in place).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — no public endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-005 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Deployment rolled out (2/2 replicas ready)
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
- [ ] AC-004: Service exists with port 80 → targetPort 8080
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
- [ ] AC-005: Pod serves HTTP 200 on port 8080 (in-cluster curl from the pod itself)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n sdd-apps deploy/app-backend -- wget -qO- http://127.0.0.1:8080/ | head -c 200"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (`sdd-apps` ns, ingress-nginx), `005-mysql-statefulset` (ordering only — the scaffold does not yet call MySQL).
- **Downstream Consumer**: `007-app-frontend-ingress` — Ingress routes `/api` → `app-backend:80` and `/` → frontend; same domain (placeholder `app.local` now, real Route53 domain later via a follow-on spec).
- **Scaffold scope**: `crccheck/hello-world` is a static HTTP responder — it does NOT connect to MySQL. The real Node.js API (ECR + MySQL client) is a later spec; this spec proves the Deployment/Service/SSM-apply pipeline for app workloads.
- **Idempotency**: `kubectl apply` is re-runnable; the `null_resource` re-triggers only when `backend_image` changes.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
