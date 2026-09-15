#!/bin/bash
# Set spec.providerID (aws:///<az>/<id>) on every node, so the AWS CCM can map
# nodes to EC2 instances for ELB target registration (004-11).
#
# Runs on the control plane via SSM Run Command (as ssm-user). Idempotent:
# re-patching a node whose providerID is already correct is a no-op.
#
# For each node, map its InternalIP -> EC2 instance ID + AZ (via the node
# instance profile's ec2:Describe* permission), then patch spec.providerID.
set -euo pipefail

K="sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl"

# Emit "name InternalIP" per line for every node.
NODES=$($K get node -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

while read -r NODE_NAME IP; do
  [ -z "${NODE_NAME}" ] && continue
  [ -z "${IP}" ] && continue

  # Map the node's InternalIP to its EC2 instance ID + AZ.
  read -r INSTANCE_ID AZ <<< $(aws ec2 describe-instances \
    --filters "Name=private-ip-address,Values=${IP}" \
    --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]' \
    --output text 2>/dev/null) || true

  if [ -z "${INSTANCE_ID}" ] || [ "${INSTANCE_ID}" = "None" ]; then
    echo "WARN: no EC2 instance found for node ${NODE_NAME} (${IP}); skipping" >&2
    continue
  fi

  PROVIDER_ID="aws://${AZ}/${INSTANCE_ID}"
  echo "Patching node ${NODE_NAME} -> ${PROVIDER_ID}"
  $K patch node "${NODE_NAME}" --type merge \
    -p "{\"spec\":{\"providerID\":\"${PROVIDER_ID}\"}}"
done <<< "${NODES}"

echo "All node providerIDs set."
