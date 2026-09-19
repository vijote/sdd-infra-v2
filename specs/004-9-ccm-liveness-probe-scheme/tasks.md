# Execution Graph (DAG): CCM Liveness Probe HTTPS Scheme

**Input**: Design documents from `/specs/004-9-ccm-liveness-probe-scheme/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 5 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Manifest] In `terraform/environments/dev/manifests/aws-ccm.yaml`: in `spec.template.spec.containers[0].livenessProbe.httpGet` (line ~90–95), add `scheme: HTTPS` — the CCM serves its health endpoint over HTTPS on the TLS-only secure port `10258`, and the probe (no `scheme`) defaulted to HTTP, so kubelet sent plaintext to a TLS port, got `400 Bad Request`, and killed the CCM on a loop (`Liveness probe failed: HTTP probe failed with statuscode: 400` → `Killing` → `BackOff`); the CCM never stayed alive long enough to finish ELB target registration, so the Ingress Service returned `curl: (52) Empty reply from server`; the upstream `cloud-provider-aws` manifest declares `scheme: HTTPS` on this exact probe — our copy dropped it; image, args (`--v=4` from 004-5), resources, and serviceAccountName stay unchanged

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T002 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001)
- [x] T003 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows only the SSM Run Command provisioner re-run (command string changed by the manifest edit), zero AWS resource create/destroy (Depends on T001)
- [x] T004 [Stage 2: Verify] AC-003: `grep -A4 'livenessProbe' terraform/environments/dev/manifests/aws-ccm.yaml | grep -c 'scheme: HTTPS'` returns `1` (Depends on T001)
- [x] T005 [Stage 2: Verify] AC-004/AC-005: after the next `terraform-apply` run (SSM re-applies the manifest + `rollout restart`) — `kubectl get pod -n kube-system -l app=aws-cloud-controller-manager -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}'` is stable across a 60s window with pod `READY 1/1`, and `kubectl get events -n kube-system` shows `0` new `Liveness probe failed` events (kill loop gone) (Depends on T001)
- [x] T006 [Stage 2: Verify] AC-006: `kubectl get svc -n ingress-nginx ingress-nginx-controller` shows EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`) + `curl -s -o /dev/null -w '%{http_code}' http://<ELB-DNS>/` returns a non-`000`/non-`52` HTTP status (ELB serves traffic, no more empty reply) — 004-4's previously-blocked ACs (Depends on T001)
