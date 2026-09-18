#!/bin/bash
# Create the Route 53 A ALIAS record for demo.vijote.dev -> the CCM-created ALB (009).
#
# Runs on the control plane via SSM Run Command (as ssm-user). The control plane uses
# the node instance profile, which carries the route53:* actions (node_route53 policy).
# Idempotent: the change-batch uses UPSERT, so re-running is a no-op.
#
# The ALB is created by the CCM (out of Terraform state), so its DNS name is read at
# runtime from the ingress-nginx Service status. The hosted zone (vijote.dev) is looked
# up by name; the user must have created it beforehand (user prerequisite).
set -euo pipefail

K="sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl"
DOMAIN="demo.vijote.dev"
ZONE_NAME="vijote.dev."
ELB_ZONE_ID="Z35SXDOTRQ7X7K"   # us-east-1 ELB hosted zone (AWS-documented)
SET_ID="demo-vijote-dev-alias"

# (1) Poll the ALB DNS name from the ingress-nginx Service status (CCM populates it).
ALB_DNS=""
for i in $(seq 1 30); do
  ALB_DNS=$($K get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) || ALB_DNS=""
  if [ -n "$ALB_DNS" ]; then
    echo "ALB DNS: $ALB_DNS"
    break
  fi
  sleep 10
done
if [ -z "$ALB_DNS" ]; then
  echo "ALB DNS not populated on ingress-nginx-controller within timeout" >&2
  exit 1
fi

# (2) Look up the vijote.dev hosted zone ID (fail fast if the user hasn't created it).
ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${ZONE_NAME}'].Id" --output text | sed 's/hostedzone\///' | head -n1)
if [ -z "$ZONE_ID" ]; then
  echo "Hosted zone ${ZONE_NAME} not found in Route 53 (user prerequisite)" >&2
  exit 1
fi
echo "Hosted zone: $ZONE_ID"

# (3) UPSERT the A ALIAS record -> ALB DNS.
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "sdd-k8s-platform ${DOMAIN} (009)",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN}.",
        "Type": "A",
        "SetIdentifier": "${SET_ID}",
        "AliasTarget": {
          "HostedZoneId": "${ELB_ZONE_ID}",
          "DNSName": "${ALB_DNS}"
        }
      }
    }
  ]
}
EOF
)
aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "$CHANGE_BATCH"
echo "Route 53 ALIAS record upserted: ${DOMAIN}. -> ${ALB_DNS}"
