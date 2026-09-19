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
