---
name: 005-ingress-nginx-service-ports-fix
description: Add the missing spec.ports block (80/HTTP, 443/HTTPS) to the ingress-nginx-controller Service so the API server accepts it and the CCM creates a valid ELB health check.
date: 2026-09-12
status: Implemented
---

# 005‑ingress‑nginx‑service‑ports‑fix

## Summary
The `ingress-nginx-controller` Service that is created by the `apply_app_frontend_ingress` provisioner is missing the mandatory `spec.ports` field.  Because of that the Service is rejected by the API server (`spec.ports: Required value`) and the AWS Cloud Controller Manager (CCM) creates a Classic ELB with a bogus health‑check (`HTTP:32238/healthz`).  The fix adds a proper `ports` block (80 → HTTP, 443 → HTTPS) and optionally forces the ELB to use an HTTP health‑check on `/healthz`.

## Motivation
* The cluster now reports **“OutOfService”** for one ELB target because the health‑check points at a non‑existent port.
* The Ingress endpoint returns **404** even when the correct Host header is sent.
* The missing `spec.ports` breaks the declarative flow that the SDD pipeline relies on – the Service never becomes *ready* and downstream specs that depend on a working ingress cannot be verified.

## Acceptance Criteria (AC)

| ID | Description |
|----|-------------|
| **AC‑001** | `kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml` contains a non‑empty `spec.ports` array with two entries (`http` on port 80, `https` on port 443). |
| **AC‑002** | After applying the spec, the Classic ELB health‑check is either `TCP:80` (default) **or** `HTTP:80/healthz` (if the optional health‑check annotations are present). |
| **AC‑003** | `aws elb describe-instance-health …` reports **both** backend instances in state `InService`. |
| **AC‑004** | `curl -H "Host: <ingress‑host>" http://<elb‑dns>/` returns **HTTP 200** and the NGINX welcome page. |
| **AC‑005** | The spec is fully reversible – removing the `ports` block (or the whole Service) restores the previous broken state, and the CI pipeline detects the regression. |

## Implementation Notes
* The Service definition lives in `terraform/environments/dev/manifests/app-frontend-ingress.yaml`.
* The spec does **not** touch the underlying Deployment; only the Service YAML is modified.
* The optional health‑check annotations are added as comments; the default (TCP 80) is sufficient for most environments.
