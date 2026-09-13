# Spec: Ingress Webhook Readiness Gate

**Feature Branch**: `007-1-ingress-webhook-readiness-gate` | **Date**: 2026-09-13 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources, no IAM, no manifests)
- **Kubernetes / Cluster Scope**: `ingress-nginx-controller` Deployment readiness (`ingress-nginx`) / `app-ingress` Ingress creation (`sdd-apps`)
- **Target Services / Modules**: `null_resource.apply_app_frontend_ingress` (007) in `terraform/environments/dev/main.tf`
- **Root Cause**: 007's SSM command applies `app-frontend-ingress.yaml` without waiting for the ingress-nginx controller to be Ready. On a fresh cluster the controller pod initially fails sandbox creation (Flannel race: `open /run/flannel/subnet.env: no such file or directory`), so the `ingress-nginx-controller-admission` Service has **no endpoints** while the controller is down. The API server's validating-webhook call for the Ingress object then fails: `failed calling webhook "validate.nginx.ingress.kubernetes.io": dial tcp <pod-ip>:443: connect: connection refused`. The Deployment and Service create fine; only the Ingress (the sole object the webhook validates) fails, and the SSM invocation returns `Failed` → `apply_app_frontend_ingress` provisioner exits 1 → `apply_aws_ccm` (004-4) is blocked by `depends_on`.

## 2. Infrastructure Contracts

### 2.1 Terraform Apply (Modify — `dev/main.tf`)
- **Target**: `null_resource.apply_app_frontend_ingress` local-exec SSM command (line ~455)
- **Change**: prepend a readiness gate to the single `&&`-chained command, before the base64 `kubectl apply`:
  ```
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s && echo '<base64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -
  ```
- **Why `rollout status`**: blocks until the controller pod is Ready (readiness probe passing ⇒ webhook listening on :8443 ⇒ admission Service endpoints populated). Idempotent on persistent clusters (returns immediately when already rolled out).
- **Re-run mechanism**: changing the `command` string changes the provisioner's computed configuration → Terraform re-runs the provisioner on the next apply (003-6 mechanism) → `kubectl apply` is idempotent (Deployment/Service `unchanged`, Ingress created).
- **Unchanged**: `depends_on`, `triggers`, SSM-agent wait, bootstrap-instance-id gate, poll loop, `--timeout-seconds 600` (rollout wait 300s + apply fits inside).

### 2.2 No Other Changes
- No new manifest, no new `null_resource`, no IAM, no module changes, no `triggers` change (the command-string change alone forces the re-run).

## 3. Acceptance Criteria

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows only the `apply_app_frontend_ingress` re-run
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2 (changes present); plan shows exactly 1 `null_resource.apply_app_frontend_ingress` to be replaced (provisioner re-run), zero other changes

- [ ] AC-003: SSM command contains the readiness gate before the apply
  ```
  terraform plan -no-color | grep -c 'rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s'
  ```
  **Expected**: `1` (gate present in the rendered command)

- [ ] AC-004: Ingress `app-ingress` exists in `sdd-apps` (created by the re-run)
  ```
  kubectl get ingress -n sdd-apps app-ingress
  ```
  **Expected**: Ingress listed with host `app.local`

- [ ] AC-005: Ingress host + paths correct
  ```
  kubectl get ingress app-ingress -n sdd-apps -o jsonpath='{.spec.rules[0].host}{.spec.rules[0].http.paths[0].path}{.spec.rules[0].http.paths[1].path}'
  ```
  **Expected**: `app.local/api/`

- [ ] AC-006: `app-frontend` Deployment rolled out
  ```
  kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=300s
  ```
  **Expected**: `deployment "app-frontend" successfully rolled out`

- [ ] AC-007: Admission webhook endpoints populated (webhook reachable)
  ```
  kubectl get endpoints ingress-nginx-controller-admission -n ingress-nginx
  ```
  **Expected**: `ENDPOINTS` = `<controller-pod-ip>:8443` (non-empty)

## 4. Out of Scope
- No fix to the Flannel sandbox race itself (transient; kubelet retries succeed — 003-11 pattern)
- No `depends_on` change (007 already runs after 004's `apply_app_infrastructure` in the same apply; the gate is in-command, not graph-level)
- No 004-4 changes (its verification gates T004–T007 unblock once this spec's apply succeeds)
- No Route53 / TLS (deferred per 004-4)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — `apply_aws_ccm` unblocks (its `depends_on` target succeeds); AC-003/004 (EXTERNAL-IP + Ingress ADDRESS) become verifiable
- **008 (ECR + real apps)** — Ingress path routing (`/api` → backend) is live on the same host
