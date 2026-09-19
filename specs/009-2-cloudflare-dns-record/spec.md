# Spec: Cloudflare DNS Record (replace Route 53)

**Feature Branch**: `009-2-cloudflare-dns-record` | **Date**: 2026-09-17 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: delete 1 IAM role policy (`node_route53`); rename + rewrite 1 SSM-driven DNS record resource (Route 53 → Cloudflare)
- **Kubernetes / Cluster Scope**: none (no manifest change)
- **Target Services / Modules**: `null_resource.apply_route53_record` (009) → renamed `apply_cloudflare_record`; `aws_iam_role_policy.node_route53` (009) → deleted; `scripts/create-route53-record.sh` → `create-cloudflare-record.sh`
- **Security & CI/CD**: Cloudflare API token via SSM SecureString (project convention); no CI/CD change

> **Why switch**: `vijote.dev` is **authoritative at Cloudflare** (its NS records point to `*.ns.cloudflare.com`), so the Route 53 ALIAS record created by 009 is **invisible to the internet** — the domain is never delegated to Route 53. The certificate is stuck `Ready=False` because Let's Encrypt's HTTP-01 challenge can't resolve. The user chose to **keep Cloudflare as the DNS authority** and create the record there. The SSM-on-control-plane pattern is unchanged; only the DNS provider call (Route 53 CLI → Cloudflare REST API) and the record type (A ALIAS → CNAME) change.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# DELETE aws_iam_role_policy.node_route53 (009) in terraform/modules/cluster-plumbing/main.tf.
# No longer needed — the record is created via the Cloudflare API, not Route 53.
# (node_ssm_parameters already grants ssm:GetParameter on /sdd-k8s-platform/*, which
#  covers the token path — NO new IAM policy is required.)

# RENAME null_resource.apply_route53_record (009) -> apply_cloudflare_record in
# terraform/environments/dev/main.tf. Same structure (depends_on, SSM-agent wait,
# bootstrap-instance-id gate, poll loop); only the embedded script + comment change.
resource "null_resource" "apply_cloudflare_record" {
  depends_on = [null_resource.apply_aws_ccm, module.cluster_plumbing]
  triggers = {
    domain      = var.ingress_host
    instance_id = module.control_plane.control_plane_instance_id # re-apply on cluster recreation
  }
  # local-exec: SSM-agent wait -> bootstrap-instance-id gate -> send-command:
  #   echo '<base64 create-cloudflare-record.sh>' | base64 -d | bash
  # --comment "Create Cloudflare CNAME record for demo.vijote.dev (009-2)"
}
```

The rename is a Terraform destroy+create of the `null_resource` (no destroy provisioner → no-op on destroy); the new resource runs on the next apply. No `depends_on` references `apply_route53_record` (009 deliberately avoided that edge to prevent a cycle), so the rename is safe.

### 1.2 SSM Script Contract — `scripts/create-cloudflare-record.sh` (replaces `create-route53-record.sh`)

```bash
#!/bin/bash
# Create the Cloudflare CNAME record for demo.vijote.dev -> the CCM-created ALB (009-2).
# Runs on the control plane via SSM Run Command (as ssm-user). The control plane uses
# the node instance profile, which carries ssm:GetParameter on /sdd-k8s-platform/*
# (node_ssm_parameters) — used to read the Cloudflare API token from SSM.
# Idempotent: GET the existing CNAME, then PUT (update) or POST (create).
set -euo pipefail
command -v curl >/dev/null 2>&1 || sudo dnf install -y curl   # defensive; AL2023 may lack curl

K="sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl"
DOMAIN="demo.vijote.dev"
ZONE_NAME="vijote.dev"
CF_API="https://api.cloudflare.com/client/v4"

# (0) Read the Cloudflare API token from SSM SecureString (user prerequisite).
CF_TOKEN=$(aws ssm get-parameter \
  --name "/sdd-k8s-platform/secrets/cloudflare-api-token" --with-decryption \
  --query 'Parameter.Value' --output text 2>/dev/null) || CF_TOKEN=""
[ -n "$CF_TOKEN" ] || { echo "Cloudflare API token not found in SSM (user prerequisite)" >&2; exit 1; }

# (1) Poll the ALB DNS name from the ingress-nginx Service status (CCM populates it).
ALB_DNS=""
for i in $(seq 1 30); do
  ALB_DNS=$($K get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) || ALB_DNS=""
  [ -n "$ALB_DNS" ] && { echo "ALB DNS: $ALB_DNS"; break; }
  sleep 10
done
[ -n "$ALB_DNS" ] || { echo "ALB DNS not populated on ingress-nginx-controller within timeout" >&2; exit 1; }

# (2) Look up the Cloudflare zone ID for vijote.dev (fail fast if absent).
ZONE_ID=$(curl -s -H "Authorization: Bearer $CF_TOKEN" "$CF_API/zones?name=$ZONE_NAME&status=active" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"]; print(r[0]["id"] if r else "")')
[ -n "$ZONE_ID" ] || { echo "Cloudflare zone $ZONE_NAME not found (user prerequisite)" >&2; exit 1; }
echo "Cloudflare zone: $ZONE_ID"

# (3) UPSERT the CNAME record -> ALB DNS. proxied=false so the ALB serves the
# Let's Encrypt cert (a proxied record would terminate TLS with Cloudflare's cert).
RECORD_ID=$(curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "$CF_API/zones/$ZONE_ID/dns_records?type=CNAME&name=$DOMAIN" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"]; print(r[0]["id"] if r else "")')
BODY="{\"type\":\"CNAME\",\"name\":\"$DOMAIN\",\"content\":\"$ALB_DNS\",\"proxied\":false}"
if [ -n "$RECORD_ID" ]; then
  curl -s -X PUT  -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
    -d "$BODY" "$CF_API/zones/$ZONE_ID/dns_records/$RECORD_ID" >/dev/null
else
  curl -s -X POST -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
    -d "$BODY" "$CF_API/zones/$ZONE_ID/dns_records" >/dev/null
fi
echo "Cloudflare CNAME record upserted: $DOMAIN -> $ALB_DNS"
```

- **JSON parsing via `python3`** (guaranteed on AL2023) — avoids a `jq` dependency.
- **`proxied: false`** is critical: the ALB must serve the Let's Encrypt cert, not Cloudflare's.
- **Token never appears in the SSM command document** — only the parameter name is embedded; the value is read on the control plane via `--with-decryption`.

### 1.3 Kubernetes Manifest Contracts
- None (no manifest change). The Ingress `tls` block + `demo-vijote-dev` Certificate (009) are unchanged.

### 1.4 Data & Storage Contracts
- **SSM SecureString** `/sdd-k8s-platform/secrets/cloudflare-api-token` — **user-created, one-time, manual** (project convention: secrets are SSM `SecureString`, NOT via Terraform or GitHub). Holds a Cloudflare API token with `Zone.DNS:Edit` on `vijote.dev`.

### 1.5 Network & Security Contracts
- **IAM**: `node_route53` deleted. No new policy — `node_ssm_parameters` already covers `ssm:GetParameter` on the token path.
- **Egress**: the control plane already has internet egress (it downloads cert-manager from GitHub), so it can reach `api.cloudflare.com`. No new SG rules.
- **Route 53 zone**: the `vijote.dev` hosted zone (user-created) is now unused; the user may delete it to stop the ~$0.50/month (manual, not a Terraform change).

## 2. Technical Acceptance Criteria

AC-001/AC-002 static (existing `terraform-apply.yml`). AC-003–AC-006 **user-managed via SSM/CLI** (P5/P6). No nslookup (AGENTS.md) — DNS+TLS+routing are proven together by the HTTPS curl in AC-006.

- [ ] AC-001: `terraform fmt -check -recursive && terraform validate`
- [ ] AC-002: `terraform plan -detailed-exitcode` — plan shows `node_route53` deletion + `apply_route53_record` destroy + `apply_cloudflare_record` create; no unexpected diffs
- [ ] AC-003: Cloudflare CNAME record present, pointing at the ALB, `proxied=false`
  ```bash
  # via SSM on the control plane (token from SSM):
  curl -s -H "Authorization: Bearer $CF_TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&name=demo.vijote.dev" | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"][0]; print(r["content"], r["proxied"])'
  # -> <ALB DNS> False
  ```
- [ ] AC-004: Certificate issued (Let's Encrypt)
  ```bash
  kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-005: `letsencrypt-prod` issuer `READY: True`
  ```bash
  kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # -> True
  ```
- [ ] AC-006: HTTPS serves frontend + backend (proves DNS resolution + TLS + routing end-to-end)
  ```bash
  curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'      # -> 200
  curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'   # -> 200 (backend)
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `009-route53-domain` (Ingress `tls` + Certificate), `004-1/004-13/004-14` (cert-manager + `letsencrypt-prod`), `004-4` (CCM/ALB), `007` (Ingress).
- **User-managed prerequisites**: (1) `vijote.dev` is a Cloudflare zone (it is); (2) SSM SecureString `/sdd-k8s-platform/secrets/cloudflare-api-token` created with a `Zone.DNS:Edit` token for `vijote.dev`.
- **Record type**: CNAME (Cloudflare has no ALIAS; a subdomain CNAME is correct). `proxied=false` so the ALB serves the Let's Encrypt cert.
- **Token delivery**: SSM SecureString (project convention) — NOT via GitHub. The token is read on the control plane; it never appears in the SSM command document or Terraform state.
- **Idempotency**: the script GETs the existing CNAME then PUT/POST (upsert); the `null_resource` re-triggers on `domain` or `instance_id` change.
- **Testing Policy**: No test generation (P6); AC-003–AC-006 are user-managed SSM/CLI checks, not added to workflows.
- **Tooling**: Terraform >= 1.5.0; control plane needs `curl` (defensively installed) + `python3` (AL2023 default).
