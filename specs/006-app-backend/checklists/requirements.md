# Technical Quality Checklist: Application Backend (Scaffold API)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-12
**Feature**: `006-app-backend`

## Technical Contracts
- [x] Terraform resource contract declared (`null_resource.apply_app_backend` with `depends_on`, `triggers`, SSM local-exec)
- [x] Kubernetes manifest contract declared (Deployment + Service, exact image, ports, probes, labels)
- [x] Image contract declared (`crccheck/hello-world:latest`, public, port 8080, pull path via NAT)
- [x] No new AWS resources (scope explicitly bounded; ECR deferred)

## Machine-Verifiable Acceptance Criteria
- [x] AC-001/AC-002 static Terraform gates (fmt, validate, plan)
- [x] AC-003 Deployment rollout via SSM (`kubectl rollout status`)
- [x] AC-004 Service port mapping via SSM (`jsonpath` port/targetPort)
- [x] AC-005 HTTP 200 from the pod via SSM (`kubectl exec ... wget`)
- [x] All SSM ACs use the `CommandInvocation.Status || Status` query (003-13 gotcha)

## Security, IAM & Network Boundaries
- [x] No secrets introduced (public image, no env, no `imagePullSecrets`)
- [x] ClusterIP only — no public exposure in this spec
- [x] No new SG rules required (003-14 VXLAN rules cover pod traffic)
- [x] kubectl via SSM Run Command on control plane (no kubeconfig in CI)

## Zero Narrative / Token Efficiency
- [x] Spec < 200 lines (95 lines)
- [x] No conversational filler; technical contracts only
- [x] Explicit upstream/downstream dependency mapping (004/005 → 006 → 007)
