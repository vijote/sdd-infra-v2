# Spec: CCM Liveness Probe HTTPS Scheme

**Feature Branch**: `004-9-ccm-liveness-probe-scheme` | **Date**: 2026-09-14 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: None (no AWS resource, IAM, or VPC change)
- **Kubernetes / Cluster Scope**: `aws-cloud-controller-manager` Deployment (`kube-system`) — liveness probe only
- **Target Services / Modules**: `terraform/environments/dev/manifests/aws-ccm.yaml` — `livenessProbe` block (line ~90–95)
- **Root Cause (confirmed via `kubectl describe pod` + CCM logs, post-004-8)**: After 004-8 granted the CCM the full `elasticloadbalancing:*` surface, the CCM started cleanly and became leader, but is killed on a loop:
  ```
  Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 400
  Normal   Killing    Container aws-cloud-controller-manager failed liveness probe, will be restarted
  Warning  BackOff    Back-off restarting failed container aws-cloud-controller-manager
  ```
  The CCM serves its health endpoint over **HTTPS** on the secure port `10258` (`Serving securely on [::]:10258`). The probe is declared without a `scheme`, so kubelet defaults to **HTTP** and sends a plaintext request to a TLS port. The HTTPS server rejects it with `400 Bad Request`, the liveness check fails, and kubelet restarts the container every ~20s. The CCM never stays alive long enough to finish ELB target registration, so the Ingress Service returns `curl: (52) Empty reply from server`.

## 2. Infrastructure Contracts

### 2.1 CCM Manifest (Modify — `terraform/environments/dev/manifests/aws-ccm.yaml`)
- **Target**: `spec.template.spec.containers[0].livenessProbe.httpGet` (line ~90–95)
- **Change**: add `scheme: HTTPS` to the `httpGet` block:
  ```yaml
  livenessProbe:
    httpGet:
      path: /healthz
      port: 10258
      scheme: HTTPS
    initialDelaySeconds: 15
    periodSeconds: 20
  ```
- **Why HTTPS**: the CCM's `--secure-port=10258` is a TLS-only endpoint. The upstream `cloud-provider-aws` manifest declares `scheme: HTTPS` on this exact probe; our copy dropped it. With `scheme: HTTPS`, kubelet performs a TLS handshake and the probe returns `200 OK`.
- **No other change**: image, args (`--cloud-provider=aws`, `--configure-cloud-routes=false`, `--cluster-name=sdd-k8s-platform`, `--v=4`), resources, serviceAccountName, and the `--v=4` flag (004-5) all stay.

### 2.2 No Other Changes
- No Terraform HCL change. The manifest is read at plan time via `base64encode(file(".../manifests/aws-ccm.yaml"))` inside the SSM Run Command provisioner (`terraform/environments/dev/main.tf` line ~540). Editing the file changes the provisioner command string, which re-triggers the SSM `kubectl apply -f -` + `rollout restart` on the next apply — no new resource, no new provisioner.
- No IAM change (004-8's `elasticloadbalancing:*` wildcard stays).
- No instance tag change (004-6 stays). No CCM version change (stays `v1.28.11-eks-1-28-64`).

## 3. Acceptance Criteria

All criteria are machine-verifiable. The `kubectl` commands run on the control plane via SSM (per the existing 004-4 deploy pattern) or from any host with `KUBECONFIG=/etc/kubernetes/admin.conf`.

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows only the CCM manifest re-apply (provisioner re-run), no resource delta
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2; plan shows the SSM/local-exec provisioner re-run for the CCM deploy, zero AWS resource create/destroy

- [ ] AC-003: Manifest contains the HTTPS scheme
  ```
  grep -A4 'livenessProbe' terraform/environments/dev/manifests/aws-ccm.yaml | grep -c 'scheme: HTTPS'
  ```
  **Expected**: `1`

- [ ] AC-004: CCM pod is Ready and stable (no liveness kill loop)
  ```
  kubectl get pod -n kube-system -l app=aws-cloud-controller-manager -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}'
  ```
  **Expected**: restart count stable (no increment across a 60s window); pod `READY 1/1`

- [ ] AC-005: No liveness probe failures in recent events
  ```
  kubectl get events -n kube-system --field-selector involvedObject.name=$(kubectl get pod -n kube-system -l app=aws-cloud-controller-manager -o jsonpath='{.items[0].metadata.name}') | grep -c 'Liveness probe failed'
  ```
  **Expected**: `0` (no new `Liveness probe failed` events after the re-apply)

- [ ] AC-006: Ingress Service EXTERNAL-IP populated and ELB serves traffic
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller
  ```
  **Expected**: EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`); `curl -s -o /dev/null -w '%{http_code}' http://<ELB-DNS>/` returns a non-`000` HTTP status (not `52` empty reply)

## 4. Out of Scope
- No CCM version change (stays `v1.28.11-eks-1-28-64`)
- No CCM arg change (`--v=4` from 004-5 stays)
- No IAM change (004-8's `elasticloadbalancing:*` wildcard stays)
- No instance tag change (004-6 stays)
- No readinessProbe addition (only the liveness probe is broken; a readiness probe is a separate concern)
- No Route53 / TLS termination (deferred)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become verifiable once the CCM stays alive and registers ELB targets
- **008 (ECR + real apps)** — Ingress path routing (`/api` → backend) is live on the ELB; end-to-end `curl -H "Host: app.local" http://<ELB-DNS>/` + `/api/` test becomes possible
