# Technical Quality Checklist: App Backend Image Fix (nginx:alpine)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: `006-1-app-backend-nginx-image`

## Technical Contracts
- [x] Root cause documented (crccheck/hello-world is not an HTTP server; probes fail → restarts)
- [x] Image contract declared (`nginx:alpine`, public, port 80, pull path via NAT)
- [x] Terraform contract declared (only `triggers.backend_image` changes — re-runs provisioner)
- [x] Manifest contract declared (4 field changes: image, containerPort, probe ports, Service targetPort)
- [x] Service `port` stays 80 — 007's Ingress `backendServicePort` unaffected

## Machine-Verifiable Acceptance Criteria
- [x] AC-001/AC-002 static Terraform gates (fmt, validate, plan)
- [x] AC-003 Deployment rollout 2/2 Ready via SSM (`kubectl rollout status`)
- [x] AC-004 Service port 80 → targetPort 80 via SSM (`jsonpath`)
- [x] AC-005 HTTP 200 via the Service from a busybox pod via SSM
- [x] All SSM ACs use the `CommandInvocation.Status || Status` query (003-13 gotcha)

## Security, IAM & Network Boundaries
- [x] No secrets introduced (public image, no env, no `imagePullSecrets`)
- [x] ClusterIP only — no public exposure
- [x] No new SG rules required
- [x] kubectl via SSM Run Command on control plane (no kubeconfig in CI)

## Zero Narrative / Token Efficiency
- [x] Spec < 200 lines (99 lines)
- [x] No conversational filler; technical contracts only
- [x] Explicit upstream/downstream dependency mapping (006 → 006-1 → 007)
