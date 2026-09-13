# Technical Quality Checklist: Ingress Webhook Readiness Gate

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-13
**Feature**: `007-1-ingress-webhook-readiness-gate`

## Infrastructure Contracts
- [x] CHK001: Single-file change — `terraform/environments/dev/main.tf` only (no new manifest, no module, no IAM)
- [x] CHK002: Readiness gate prepended to the existing `&&`-chained SSM command (not a new command, not a new `null_resource`)
- [x] CHK003: Gate targets `deployment/ingress-nginx-controller -n ingress-nginx` with `--timeout=300s` (matches 004-4's CCM rollout-wait pattern)
- [x] CHK004: `KUBECONFIG=/etc/kubernetes/admin.conf` prefix on the gate (SSM minimal-env gotcha, 003-9)
- [x] CHK005: `depends_on`, `triggers`, SSM-agent wait, bootstrap-instance-id gate, poll loop, `--timeout-seconds 600` all unchanged

## Re-run / Idempotency
- [x] CHK006: Command-string change forces provisioner re-run on next apply (003-6 mechanism)
- [x] CHK007: `kubectl apply` idempotent — Deployment/Service `unchanged`, Ingress created on re-run
- [x] CHK008: `rollout status` returns immediately on persistent clusters (no added latency to steady-state applies)

## Root Cause Coverage
- [x] CHK009: Gate blocks until controller Ready ⇒ webhook listening on :8443 ⇒ admission Service endpoints populated (verified: endpoints `192.168.1.10:8443` after controller recovered)
- [x] CHK010: Failure mode addressed is the Ingress-only webhook rejection (`validate.nginx.ingress.kubernetes.io` connection refused) — Deployment/Service creation unaffected

## Acceptance Criteria
- [x] CHK011: All 7 ACs machine-verifiable (terraform fmt/validate/plan + kubectl get/rollout/endpoints)
- [x] CHK012: AC-002 pins the plan delta to exactly 1 `null_resource` re-run (no collateral changes)
- [x] CHK013: AC-003 greps the rendered plan for the gate string (proves the command change is live)
- [x] CHK014: AC-004/AC-005 confirm the Ingress exists with correct host + paths (the object that previously failed)
- [x] CHK015: AC-007 confirms webhook endpoints populated (the precondition the gate enforces)

## Scope Discipline
- [x] CHK016: No Flannel-race fix (transient, kubelet retries — out of scope)
- [x] CHK017: No 004-4 changes (its T004–T007 unblock downstream)
- [x] CHK018: No Route53 / TLS (deferred per 004-4)
