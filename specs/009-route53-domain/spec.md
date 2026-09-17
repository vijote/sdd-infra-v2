# Spec: Route 53 Domain + Let's Encrypt TLS

**Feature Branch**: `009-route53-domain` | **Date**: 2026-09-16 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: 1 Route 53 ALIAS record (via SSM, not Terraform — the ALB is CCM-created, out of state) + 1 node-role IAM policy (Route 53 actions)
- **Kubernetes / Cluster Scope**: `app-ingress` Ingress `tls` block + `demo-vijote-dev` Certificate (cert-manager, `letsencrypt-prod` issuer) in `sdd-apps`
- **Target Services / Modules**: ingress-nginx LoadBalancer (004), cert-manager + `letsencrypt-prod` ClusterIssuer (004-1/004-13/004-14), `app-ingress` Ingress (007)
- **Security & CI/CD**: SSM Run Command on control plane (003-3/003-11 pattern); node-role Route 53 IAM (dev-only wildcard, 004-8 precedent)

> **Prerequisite (user-managed)**: the `vijote.dev` hosted zone must exist in Route 53 (the user owns the domain). The SSM command looks up the zone ID dynamically by name; if absent, the apply fails fast.

### 1.1 Why SSM, not a Terraform `aws_route53_record`
The ALB is created by the CCM at runtime (out of Terraform state) — its DNS name is unknown at plan time, so a Terraform `aws_route53_record` (or `data "aws_lb"`) cannot resolve the target on first apply. The record is therefore created via SSM on the control plane, after `apply_aws_ccm` (ALB exists), reading the ALB DNS name from the ingress-nginx Service status.

### 1.2 Terraform / HCL Resource Contracts

```hcl
# terraform/environments/dev/variables.tf — real domain (was "app.local")
variable "ingress_host" {
  type        = string
  description = "Ingress host (Route53 domain)"
  default     = "demo.vijote.dev"
}

# terraform/environments/dev/main.tf — new resource; depends on CCM (ALB must exist)
resource "null_resource" "apply_route53_record" {
  depends_on = [null_resource.apply_aws_ccm]
  triggers   = { domain = var.ingress_host, instance_id = module.control_plane.control_plane_instance_id }
  # local-exec: SSM-agent wait -> bootstrap-instance-id gate (003-11) -> send-command:
  #   (1) poll kubectl for the ingress-nginx Service ALB DNS name (30x10s)
  #   (2) aws route53 list-hosted-zones -> vijote.dev zone ID (fail fast if absent)
  #   (3) aws route53 change-resource-record-set UPSERT A ALIAS demo.vijote.dev. -> ALB DNS
  #       (SetIdentifier demo-vijote-dev-alias; AliasTarget.HostedZoneId Z35SXDOTRQ7X7K = us-east-1 ELB zone)
}

# terraform/environments/dev/main.tf — apply_app_frontend_ingress gains two deps so the
# Ingress+Certificate apply only after the domain is live and the issuers exist:
#   depends_on = [null_resource.apply_app_backend,
#                 null_resource.apply_route53_record,
#                 null_resource.apply_cert_manager]

# terraform/modules/cluster-plumbing/main.tf — new node-role policy (mirrors node_aws_ccm)
resource "aws_iam_role_policy" "node_route53" {
  name = "sdd-k8s-platform-node-route53"
  role = aws_iam_role.node.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone"]
      Resource = "*" # dev-only (004-8 wildcard precedent); scope to the vijote.dev zone ID in prod
    }]
  })
}
```

### 1.3 Kubernetes Manifest Contracts

`terraform/environments/dev/manifests/app-frontend-ingress.yaml` — two additions:
- **Ingress `app-ingress`** — add `spec.tls` (host stays `%%INGRESS_HOST%%`):
  ```yaml
  spec:
    tls:
      - hosts: ["%%INGRESS_HOST%%"]
        secretName: demo-vijote-dev-tls
    rules:
      - host: %%INGRESS_HOST%%
        # ...existing /api and / path rules unchanged
  ```
- **Certificate `demo-vijote-dev`** (new object, `sdd-apps`):
  ```yaml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata: { name: demo-vijote-dev, namespace: sdd-apps }
  spec:
    secretName: demo-vijote-dev-tls
    dnsNames: ["%%INGRESS_HOST%%"]
    issuerRef: { name: letsencrypt-prod, kind: ClusterIssuer }
  ```

### 1.4 Data & Storage Contracts
- N/A (the TLS secret `demo-vijote-dev-tls` is created by cert-manager at issuance).

### 1.5 Network & Security Contracts
- The ALB SG already allows 443 (004-7). No new SG rules.
- HTTP-01: Let's Encrypt validates `http://demo.vijote.dev/.well-known/acme-challenge/...` -> ALB -> ingress-nginx -> cert-manager solver. Requires the Route 53 record live + ingress controller running.

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml`). AC-003–AC-006 **user-managed via SSM/CLI** (P5/P6). No nslookup (AGENTS.md) — DNS+TLS+routing are proven together by the HTTPS curl in AC-006.

- [ ] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows the new `null_resource.apply_route53_record` + `aws_iam_role_policy.node_route53` + the `apply_app_frontend_ingress` re-apply (ingress_host change); no unexpected diffs
- [ ] AC-003: Route 53 ALIAS record present, pointing at the ALB
  ```bash
  aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?Name=='demo.vijote.dev.'].AliasTarget.DNSName" --output text
  ```
- [ ] AC-004: Certificate issued (Let's Encrypt)
  ```bash
  kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-005: `letsencrypt-prod` issuer now `READY: True` (ACME account registered on first issuance)
  ```bash
  kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-006: HTTPS serves frontend + backend (proves DNS resolution + TLS + routing end-to-end)
  ```bash
  curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'      # -> 200
  curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'   # -> 200 (backend)
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `004-1/004-13/004-14` (cert-manager + `letsencrypt-prod`), `004-4` (CCM/ALB), `007` (Ingress).
- **User-managed prerequisite**: `vijote.dev` hosted zone exists in Route 53.
- **ELB zone ID**: `Z35SXDOTRQ7X7K` (us-east-1 ELB hosted zone, AWS-documented; single-region dev project).
- **DNS propagation**: ALIAS records propagate in seconds–minutes; cert-manager retries failed HTTP-01 challenges automatically, so a slow first validation self-heals (no nslookup wait, per AGENTS.md).
- **Idempotency**: `change-resource-record-set` uses `UPSERT`; the `null_resource` re-triggers on `domain` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-006 are user-managed SSM/CLI checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0.
