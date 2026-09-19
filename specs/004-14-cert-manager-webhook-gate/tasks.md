# Execution Graph (DAG): cert-manager Webhook Readiness Gate

**Input**: Design documents from `/specs/004-14-cert-manager-webhook-gate/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Platform] In `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager` (004-1/004-13): (1) `triggers.cert_manager_ref` `"v1.19.4"` → `"v1.19.4+webhook-gate"` (update the `# 004-13` comment to note 004-14's gate), (2) SSM `--parameters` first command: chain after the `kubectl apply -f .../v1.19.4/cert-manager.yaml` with `&& KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=300s`, (3) `--comment` → `"Deploy cert-manager v1.19.4 + webhook gate + ClusterIssuers (004-1/004-13/004-14)"`. Do NOT touch: second SSM command (base64 issuers apply), SSM-agent wait loop, bootstrap-instance-id gate, poll loop, `depends_on`, `instance_id` trigger, or `manifests/cert-manager-issuers.yaml`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T002 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [x] T003 [Stage 2: Verify] AC-003: controller + webhook + cainjector pods Ready (via SSM: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s` + `-webhook` + `-cainjector`)
- [x] T004 [Stage 2: Verify] AC-004/AC-005: both ClusterIssuers present (`kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`) AND both report `READY: True` (`kubectl get clusterissuer selfsigned letsencrypt-prod -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'`) (via SSM)
- [x] T005 [Stage 2: Verify] AC-006: the `apply_cert_manager` SSM invocation `Status == Success` with no webhook `connection refused` in StdErr (via SSM: `aws ssm get-command-invocation --command-id <CID> --instance-id <IID> --query 'CommandInvocation.Status' --output text`)
