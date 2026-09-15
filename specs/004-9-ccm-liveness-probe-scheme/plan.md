# Architecture Delta: CCM Liveness Probe HTTPS Scheme

**Branch**: `004-9-ccm-liveness-probe-scheme` | **Date**: 2026-09-14 | **Spec**: [specs/004-9-ccm-liveness-probe-scheme/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Change |
|------|-----------|--------|
| `terraform/environments/dev/manifests/aws-ccm.yaml` | Modify | In `spec.template.spec.containers[0].livenessProbe.httpGet` (lines ~90–95), add `scheme: HTTPS`. No other field, arg, image, or resource change. |

## 2. Architectural Boundaries & Dependency Flow

- **Manifest Layer**: `aws-ccm.yaml` is a raw `apps/v1` Deployment in `kube-system`, applied via SSM Run Command (`base64encode(file(...))` → `kubectl apply -f -` → `rollout restart`) in `terraform/environments/dev/main.tf` (line ~540).
- **Consumer**: `aws-cloud-controller-manager` pod — the liveness probe must speak HTTPS to the CCM's TLS-only secure port `10258`.
- **No graph change**: no new resource, no HCL change, no `depends_on` change, no IAM change. Editing the manifest changes the provisioner command string, which re-triggers the SSM `kubectl apply` + `rollout restart` on the next apply.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` → the SSM Run Command provisioner re-runs (command string changed by the manifest edit) → `kubectl apply -f -` updates the Deployment in place → `rollout restart` recreates the CCM pod with the corrected probe.
2. **Stage 2 - CCM stability**: the new pod's liveness probe performs a TLS handshake against `10258` and returns `200 OK`. The kill loop stops; the pod stays `1/1 Ready` and the restart count stops incrementing.
3. **Stage 3 - ELB registration**: with the CCM alive, `EnsureLoadBalancer` completes target registration on the existing ELB → `ingress-nginx-controller` Service EXTERNAL-IP is populated and the ELB serves traffic (no more `curl: (52)`).

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Plan Delta**: `terraform plan -detailed-exitcode` → exit 2, only the SSM provisioner re-run, zero AWS resource create/destroy
- **Manifest Content**: `grep -A4 'livenessProbe' terraform/environments/dev/manifests/aws-ccm.yaml | grep -c 'scheme: HTTPS'` → `1`
- **CCM Stability**: `kubectl get pod -n kube-system -l app=aws-cloud-controller-manager -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}'` → stable across a 60s window, pod `READY 1/1`
- **No Liveness Failures**: `kubectl get events -n kube-system ... | grep -c 'Liveness probe failed'` → `0` new events
- **Service Endpoint**: `kubectl get svc -n ingress-nginx ingress-nginx-controller` → EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com`; `curl` to the ELB returns a non-`000`/non-`52` HTTP status

## 5. Key Decisions

- **`scheme: HTTPS`, not a port change**: the CCM's `--secure-port=10258` is TLS-only by design. The upstream `cloud-provider-aws` manifest declares `scheme: HTTPS` on this exact probe; our copy dropped it. Adding the scheme is the minimal, upstream-aligned fix.
- **No readinessProbe added**: only the liveness probe is broken. A readiness probe is a separate concern and out of scope for this fix.
- **No CCM version/arg/IAM change**: stays on `v1.28.11-eks-1-28-64`, `--v=4` (004-5), instance tag (004-6), and `elasticloadbalancing:*` wildcard (004-8) all stay.
