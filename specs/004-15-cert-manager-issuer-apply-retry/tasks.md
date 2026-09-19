# Execution Graph (DAG): cert-manager ClusterIssuer Apply Retry

**Input**: Design documents from `/specs/004-15-cert-manager-issuer-apply-retry/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Platform] In `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager` (004-1/004-13/004-14): (1) `triggers.cert_manager_ref` `"v1.19.4+webhook-gate"` → `"v1.19.4+webhook-gate+issuer-retry"` (update the `# 004-14` comment to note 004-15's retry), (2) SSM `--parameters` **second** command (the base64 `cert-manager-issuers.yaml` apply): wrap it in a bounded retry loop — `for i in $(seq 1 10); do if echo '<b64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -; then echo "ClusterIssuers applied successfully"; exit 0; fi; echo "ClusterIssuer apply attempt $${i} failed, retrying in 5s" >&2; sleep 5; done; echo "ClusterIssuer apply failed after 10 attempts" >&2; exit 1` (keep the `${base64encode(file("${path.module}/manifests/cert-manager-issuers.yaml"))}` interpolation; write the shell loop var as `$${i}` so Terraform passes a literal `$i` to the shell; `$(seq 1 10)` passes through the heredoc literally), (3) `--comment` → `"Deploy cert-manager v1.19.4 + webhook gate + ClusterIssuers + retry (004-1/004-13/004-14/004-15)"` (SSM `--comment` is capped at 100 chars — keep it under). Implementation note: the loop uses an explicit `1 2 3 4 5 6 7 8 9 10` list (no `$(seq)`) and single-quoted echo messages (no per-attempt counter) to avoid heredoc escaping. Do NOT touch: first SSM command (cert-manager.yaml apply + webhook/cainjector rollout gates), SSM-agent wait loop, bootstrap-instance-id gate, poll loop, `depends_on`, `instance_id` trigger, `--timeout-seconds 600`, or `manifests/cert-manager-issuers.yaml`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T002 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [x] T003 [Stage 2: Verify] AC-003: both ClusterIssuers present (via SSM: `kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`)
- [x] T004 [Stage 2: Verify] AC-004/AC-006: both ClusterIssuers report `READY: True` (via SSM: `kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'`) AND the webhook is callable (via SSM: `kubectl get clusterissuers >/dev/null && echo "webhook OK"` → `webhook OK`)
- [x] T005 [Stage 2: Verify] AC-005: the `apply_cert_manager` SSM invocation `Status == Success` with no webhook `connection refused` in StdErr (via SSM: `aws ssm get-command-invocation --command-id <CID> --instance-id <IID> --query 'CommandInvocation.Status' --output text`)
