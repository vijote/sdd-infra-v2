#!/usr/bin/env bash
# ECR pull secret (011-ecr-pull-secret) — runs on the control plane via SSM.
# Creates/refreshes the dockerconfigjson secret `ecr-pull-secret` in sdd-apps so
# kubelet can pull from ECR. The ECR token is valid ~12h; re-run to refresh.
set -euo pipefail

REGISTRY="%%ECR_REGISTRY%%" # replaced by Terraform with the 010 ECR repository URL

if [ -z "$REGISTRY" ] || [ "$REGISTRY" = "%%ECR_REGISTRY%%" ]; then
  echo "ERROR: REGISTRY not substituted" >&2
  exit 1
fi

# Mint a fresh ECR token (node role has AmazonEC2ContainerRegistryReadOnly).
PASSWORD=$(aws ecr get-login-password)
if [ -z "$PASSWORD" ]; then
  echo "ERROR: aws ecr get-login-password returned empty" >&2
  exit 1
fi

# Idempotent: delete then create (kubectl apply cannot update dockerconfigjson data).
KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete secret ecr-pull-secret -n sdd-apps --ignore-not-found
KUBECONFIG=/etc/kubernetes/admin.conf kubectl create secret docker-registry ecr-pull-secret \
  -n sdd-apps \
  --docker-server="$REGISTRY" \
  --docker-username=AWS \
  --docker-password="$PASSWORD"

echo "ECR pull secret created in sdd-apps (registry: $REGISTRY)"
