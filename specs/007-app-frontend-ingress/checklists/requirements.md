# Technical Quality Checklist: Application Frontend + Ingress

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: `007-app-frontend-ingress`

## Technical Contracts
- [x] Image contract declared (`nginx:alpine`, public, port 80, pull path via NAT)
- [x] Terraform contracts declared (`ingress_host` var with `app.local` default; `null_resource.apply_app_frontend_ingress` with `depends_on`, `triggers`, SSM local-exec)
- [x] Manifest contract declared (Deployment + Service + Ingress, exact host, path rules `/api` + `/`)
- [x] `%%INGRESS_HOST%%` token replaced with `var.ingress_host` before base64 (005 pattern, non-secret)
- [x] No new AWS resources (ingress-nginx LoadBalancer already exists from 004)

## Machine-Verifiable Acceptance Criteria
- [x] AC-001/AC-002 static Terraform gates (fmt, validate, plan)
- [x] AC-003 Frontend Deployment rollout via SSM (`kubectl rollout status`)
- [x] AC-004 Ingress host + both path rules via SSM (`jsonpath`)
- [x] AC-005 Ingress external ADDRESS (LoadBalancer IP) via SSM
- [x] AC-006 Path routing `/` + `/api/` → HTTP 200 via ingress controller (Host header) via SSM
- [x] All SSM ACs use the `CommandInvocation.Status || Status` query (003-13 gotcha)

## Security, IAM & Network Boundaries
- [x] No secrets introduced (public image; host is a non-secret var)
- [x] No new LoadBalancer / SG rules (reuses 004's ingress-nginx LB)
- [x] kubectl via SSM Run Command on control plane (no kubeconfig in CI)

## Zero Narrative / Token Efficiency
- [x] Spec < 200 lines (117 lines)
- [x] No conversational filler; technical contracts only
- [x] Explicit upstream/downstream dependency mapping (004/006 → 007 → 008)
