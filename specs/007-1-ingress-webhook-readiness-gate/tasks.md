# Execution Graph (DAG): Ingress Webhook Readiness Gate

**Input**: Design documents from `/specs/007-1-ingress-webhook-readiness-gate/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 5 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`: in `null_resource.apply_app_frontend_ingress`'s local-exec `command` heredoc, prepend the readiness gate to the SSM `--parameters` command string (line ~455) so it reads `\"KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s && echo '<base64...>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\"` — the gate blocks until the controller is Ready (webhook on :8443, admission endpoints populated) before the Ingress is applied; `depends_on`, `triggers`, SSM-agent wait, bootstrap-instance-id gate, poll loop, and `--timeout-seconds 600` are unchanged

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T002 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows exactly 1 `null_resource.apply_app_frontend_ingress` re-run, zero other changes (Depends on T001)
- [ ] T004 [Stage 2: Verify] AC-003: `terraform plan -no-color | grep -c 'rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s'` returns `1` (gate present in the rendered command) (Depends on T001)
- [ ] T005 [Stage 2: Verify] AC-004/AC-005/AC-006: after the next `terraform-apply` run — `kubectl get ingress -n sdd-apps app-ingress` (host `app.local`) + jsonpath host/paths = `app.local/api/` + `kubectl rollout status deployment/app-frontend -n sdd-apps --timeout=300s` (Depends on T001)
- [ ] T006 [Stage 2: Verify] AC-007: `kubectl get endpoints ingress-nginx-controller-admission -n ingress-nginx` — ENDPOINTS non-empty (`<controller-pod-ip>:8443`) (Depends on T001)
