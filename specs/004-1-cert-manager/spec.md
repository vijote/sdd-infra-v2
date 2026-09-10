# Spec: cert-manager + Let's Encrypt (TLS Automation)

**Feature Branch**: `004-1-cert-manager` | **Date**: 2026-09-09 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: cert-manager (CRDs + controller) / ClusterIssuers / TLS certificate automation
- **Kubernetes / Cluster Scope**: `cert-manager` namespace / cert-manager controller + webhook + cainjector / `Certificate` CRD
- **Target Services / Modules**: cert-manager (`v1.21.1`), `selfsigned` ClusterIssuer (default, no DNS), `letsencrypt-prod` ClusterIssuer (HTTP-01)
- **Security & CI/CD**: all `kubectl` applies via SSM Run Command on the control plane; no IRSA (kubeadm has no OIDC provider)

> **Prerequisite**: `004-app-infrastructure` (Ready 3-node cluster, ingress controller with a public LB hostname). cert-manager issues certs for Ingress resources created in `005-app-deployment`.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# kubectl applies — version-controlled null_resource in the dev env (Flannel pattern, 003-3/003-11).
# Runs on the CI runner; issues `aws ssm send-command` to the control plane. The actual
# `kubectl apply` runs there with KUBECONFIG=/etc/kubernetes/admin.conf. Idempotent (kubectl apply).
resource "null_resource" "apply_cert_manager" {
  depends_on = [null_resource.apply_app_infrastructure]
  triggers = {
    cert_manager_ref = "v1.21.1"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail
      INSTANCE_ID="${module.control_plane.control_plane_instance_id}"
      # SSM-agent wait + bootstrap-instance-id gate (identical to 003-11 Flannel gate).
      for i in $(seq 1 30); do
        SSM_ID=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$${INSTANCE_ID}" \
          --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null) || SSM_ID="Pending"
        [ "$${SSM_ID}" = "$${INSTANCE_ID}" ] && break; sleep 10
      done
      for i in $(seq 1 60); do
        BOOTSTRAP_ID=$(aws ssm get-parameter --name "/sdd-k8s-platform/kubeadm-bootstrap-instance-id" \
          --query 'Parameter.Value' --output text 2>/dev/null) || BOOTSTRAP_ID=""
        [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ] && break; sleep 10
      done
      [ "$${BOOTSTRAP_ID}" = "$${INSTANCE_ID}" ] || { echo "bootstrap gate timeout" >&2; exit 1; }
      CMD_ID=$(aws ssm send-command --instance-ids "$${INSTANCE_ID}" \
        --document-name AWS-RunShellScript \
        --parameters "commands=[
          \"KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml\",
          \"echo '<CLUSTER_ISSUERS_BASE64>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -\"
        ]" --timeout-seconds 600 --query 'Command.CommandId' --output text)
      for i in $(seq 1 60); do
        STATUS=$(aws ssm get-command-invocation --instance-id "$${INSTANCE_ID}" --command-id "$${CMD_ID}" \
          --query 'CommandInvocation.Status || Status' --output text 2>/dev/null) || STATUS="Pending"
        [ "$${STATUS}" = "Success" ] && exit 0
        { [ "$${STATUS}" = "Failed" ] || [ "$${STATUS}" = "TimedOut" ] || [ "$${STATUS}" = "Cancelled" ]; } && { echo "apply failed: $${STATUS}" >&2; exit 1; }
        sleep 10
      done
      echo "apply timed out" >&2; exit 1
    EOT
  }
}
```

### 1.2 Kubernetes Manifest / Helm Values Contracts

- **cert-manager** — static manifest `v1.21.1` (creates `cert-manager` namespace, CRDs, `cert-manager` controller Deployment, `cert-manager-webhook`, `cert-manager-cainjector`).
- **ClusterIssuers** (base64-encoded into the SSM command to avoid JSON-escaping, per 003-6):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx
```
- **Certificate** (consumed by 005 Ingress): `issuerRef: selfsigned` (default, no DNS required) or `letsencrypt-prod` (requires a resolvable domain pointing at the ingress LB).

### 1.3 Data & Storage Contracts
- **Certificate Secrets**: cert-manager stores issued certs in Kubernetes Secrets (e.g. `<cert-name>` Secret with `tls.crt`/`tls.key`).
- **ACME account key**: `letsencrypt-prod-account-key` Secret (auto-created by cert-manager on first issuance).

### 1.4 Network & Security Contracts
- **HTTP-01 challenge**: Let's Encrypt validates `http://<domain>/.well-known/acme-challenge/<token>` via the nginx ingress controller (ingress class `nginx`).
- **selfsigned issuer**: no external network dependency — usable immediately for dev TLS without a domain.
- **No IRSA**: cert-manager pods run on nodes; no AWS API access required.

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-006 execute **on the control plane via SSM** (`aws ssm send-command` + poll `aws ssm get-command-invocation` until `Status` = `Success`) — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-006 are **user-managed verification** (defined here, not added to `terraform-apply.yml`).

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: cert-manager controller + webhook + cainjector ready
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=cert-manager-webhook -n cert-manager --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=cert-manager-cainjector -n cert-manager --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-004: selfsigned ClusterIssuer present
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get clusterissuer selfsigned -o jsonpath={.metadata.name}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '^selfsigned$'
  ```
- [ ] AC-005: letsencrypt-prod ClusterIssuer present
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get clusterissuer letsencrypt-prod -o jsonpath={.metadata.name}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '^letsencrypt-prod$'
  ```
- [ ] AC-006: cert-manager CRDs installed (Certificate, ClusterIssuer, Issuer)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get crd certificates.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io -o name | wc -l"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '^3$'
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-app-infrastructure` (Ready cluster, nginx ingress controller with public LB hostname).
- **Downstream Consumer**: `005-app-deployment` (Ingress resources reference `selfsigned` or `letsencrypt-prod` ClusterIssuer for TLS).
- **selfsigned default**: dev TLS works immediately without a domain; `letsencrypt-prod` requires a resolvable domain pointing at the ingress LB (configured in 005).
- **No IRSA**: cert-manager pods run on nodes; no AWS API access required.
- **Idempotency**: all `kubectl apply` operations are re-runnable; the `null_resource` re-triggers only on a pinned-version change.
- **Testing Policy**: No unit or E2E test generation — validation performed via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
