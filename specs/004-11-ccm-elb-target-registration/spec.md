---
name: 004-11-ccm-elb-target-registration
description: Set spec.providerID on all nodes (bootstrap patch) and add get+watch on services to the CCM ClusterRole so the CCM can map nodes to instances and register ELB targets.
date: 2026-09-15
status: Implemented
---

# Spec: CCM ELB Target Registration (Node providerID + RBAC)

**Feature Branch**: `004-11-ccm-elb-target-registration` | **Date**: 2026-09-15 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform (one new `null_resource`), two bootstrap scripts, one CCM manifest RBAC block
- **Kubernetes / Cluster Scope**: node `spec.providerID` (all 3 nodes), CCM ClusterRole (`kube-system`)
- **Target Services / Modules**: `terraform/modules/control-plane/bootstrap.sh`, `terraform/modules/worker-nodes/bootstrap.sh`, `terraform/environments/dev/manifests/aws-ccm.yaml`, `terraform/environments/dev/main.tf`
- **Root Cause (confirmed via CCM logs + `kubectl auth can-i`, post-004-10)**: The CCM creates the ELB and assigns the Ingress Service EXTERNAL-IP, but **never registers the target instances** → `aws elb describe-load-balancers` shows `Instances: []` → `curl` → `000`. Two independent defects:
  1. **Nodes have no `spec.providerID`** (the smoking gun):
     ```
     node_controller.go:281] Error getting instance metadata for node addresses:
       error fetching node by provider ID: Invalid format for AWS instance (),
       and error by node name: could not look up instance ID for node "control-plane-0": node has no providerID
     ```
     The CCM's default `--aws-node-name=NodeNameProviderID` resolves a node to an EC2 instance by parsing the node name as a providerID (`aws:///<az>/<id>`). The node names (`control-plane-0`, `ip-10-0-12-59.ec2.internal`) are not providerIDs, and `spec.providerID` is empty, so the CCM cannot map nodes → instances → **no ELB targets**. Neither `kubeadm init` (control plane) nor the worker `kubeadm join` sets a `providerID`.
  2. **CCM ClusterRole RBAC gap** (confirmed by `kubectl auth can-i`):
     ```
     watch services -> no
     get services   -> no
     ```
     The `services` rule has `["list","patch","update","create","delete"]` (no `watch`/`get`); `services/status` has `["list","patch","update"]` (no `watch`/`get`). This causes the repeating `Failed to watch *v1.Service: unknown (get services)` error.
- **Note on 004-10/004-9**: both are verified working (3 nodes `Ready`, Flannel `3/3`, CCM `1/1 Running` with `scheme: HTTPS`, healthz `200`, EXTERNAL-IP assigned). This spec fixes the two remaining defects that prevent ELB target registration.

## 2. Infrastructure Contracts

### 2.1 CCM ClusterRole RBAC (Modify — `terraform/environments/dev/manifests/aws-ccm.yaml`)
- **Target**: the `system:aws-cloud-controller-manager` ClusterRole `rules` (lines ~22–49)
- **Change**: add `get` + `watch` to the `services` and `services/status` rules:
  ```yaml
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "patch", "update", "create", "delete"]
  - apiGroups: [""]
    resources: ["services/status"]
    verbs: ["get", "list", "watch", "patch", "update"]
  ```
- **Why**: the CCM's Service informer needs `watch` (and `get` for resync) to maintain the ELB target set. The upstream `cloud-provider-aws` RBAC grants `get`/`list`/`watch` on `services`.

### 2.2 Control-Plane Bootstrap (Modify — `terraform/modules/control-plane/bootstrap.sh`)
- **Target**: the IMDS fetch block (lines ~15–27) and the `kubeadm-config.yaml` `nodeRegistration` (lines ~72–74)
- **Change**:
  1. Fetch the AZ via IMDSv2 (alongside the existing `PRIVATE_IP`/`INSTANCE_ID`):
     ```bash
     AZ=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
       http://169.254.169.254/latest/meta-data/placement/availability-zone)
     ```
     and extend the fail-fast guard to include `AZ`.
  2. Configure kubelet extra args with provider-id:
     ```yaml
     nodeRegistration:
       name: control-plane-0
       criSocket: unix:///run/containerd/containerd.sock
       kubeletExtraArgs:
         provider-id: aws://${AZ}/${INSTANCE_ID}
     ```
     and `/etc/sysconfig/kubelet` with `KUBELET_EXTRA_ARGS="--provider-id=aws://${AZ}/${INSTANCE_ID}"`.
- **Why**: sets the control-plane node's `spec.providerID` at `kubeadm init` time, so the CCM can resolve it to an EC2 instance.

### 2.3 Worker Bootstrap (Modify — `terraform/modules/worker-nodes/bootstrap.sh`)
- **Target**: the top of the script (after the `K8S_VERSION`/`SSM_PARAM_NAME` block, ~line 12) and the `eval "${JOIN_COMMAND}"` (line ~79)
- **Change**:
  1. Add an IMDSv2 fetch block (token + `INSTANCE_ID` + `AZ`) with a fail-fast guard, mirroring the control-plane pattern:
     ```bash
     IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
       -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
     INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
       http://169.254.169.254/latest/meta-data/instance-id)
     AZ=$(curl -s -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
       http://169.254.169.254/latest/meta-data/placement/availability-zone)
     [ -n "${INSTANCE_ID}" ] && [ -n "${AZ}" ] || { echo "IMDS fetch failed" >&2; exit 1; }
     ```
  2. Configure `/etc/sysconfig/kubelet` with `KUBELET_EXTRA_ARGS="--provider-id=aws://${AZ}/${INSTANCE_ID}"` before joining (kubeadm join does not take a `--provider-id` CLI flag):
     ```bash
     mkdir -p /etc/sysconfig
     echo "KUBELET_EXTRA_ARGS=\"--provider-id=aws://${AZ}/${INSTANCE_ID}\"" > /etc/sysconfig/kubelet
     eval "${JOIN_COMMAND}"
     ```
- **Why**: sets each worker node's `spec.providerID` at `kubelet` registration time.

### 2.4 Node providerID Repair (New — `terraform/environments/dev/main.tf`)
- **Target**: a new `null_resource` `set_node_provider_ids`, inserted into the apply chain before `apply_aws_ccm` (i.e. `apply_aws_ccm` gains `depends_on = [null_resource.set_node_provider_ids, ...]`, or the new resource is chained between `apply_app_frontend_ingress` and `apply_aws_ccm`)
- **Change**: an SSM Run Command on the control plane that patches `spec.providerID` on every node (idempotent — re-patching the same value is a no-op). For each node, map its InternalIP → EC2 instance ID + AZ, then patch:
  ```bash
  K="sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl"
  for ip in $($K get node -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
    read -r INSTANCE_ID AZ <<< $(aws ec2 describe-instances \
      --filters "Name=private-ip-address,Values=${ip}" \
      --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]' --output text)
    NODE_NAME=$($K get node -o json | jq -r --arg ip "$ip" \
      '.items[] | select(.status.addresses[]? | select(.type=="InternalIP" and .address==$ip)) | .metadata.name')
    $K patch node "$NODE_NAME" --type merge -p "{\"spec\":{\"providerID\":\"aws://${AZ}/${INSTANCE_ID}\"}}"
  done
  ```
- **Triggers**: `instance_id = module.control_plane.control_plane_instance_id` (re-runs on recreation, per 004-10) + a version key (e.g. `provider_id_ref = "1"`).
- **Why**: the bootstrap fixes (2.2/2.3) only apply to *future* cluster recreations. The current cluster's nodes already booted without a `providerID`, so this one-time (idempotent) repair patches them in place — no `terraform destroy` needed.

### 2.5 No Other Changes
- No CCM version/arg change (stays `v1.28.11-eks-1-28-64`, `--v=4`, `scheme: HTTPS` from 004-9).
- No node IAM change (the `node_aws_ccm` policy already has `ec2:Describe*` + `ec2:RegisterInstancesWithLoadBalancer`).
- No instance tag change (004-6 stays). No VPC/SG change.

## 3. Acceptance Criteria

All criteria are machine-verifiable. The `kubectl`/`aws` commands run on the control plane via SSM (per the existing apply pattern) or from any host with `KUBECONFIG=/etc/kubernetes/admin.conf`.

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: CCM ClusterRole grants `watch` + `get` on `services`
  ```
  kubectl auth can-i watch services --as=system:serviceaccount:kube-system:aws-cloud-controller-manager
  kubectl auth can-i get services --as=system:serviceaccount:kube-system:aws-cloud-controller-manager
  ```
  **Expected**: `yes` / `yes`

- [ ] AC-003: Every node has a `spec.providerID` in `aws:///<az>/<id>` form
  ```
  kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'
  ```
  **Expected**: 3 lines, each `providerID` matching `aws://us-east-1a/i-...` (non-empty, correct format)

- [ ] AC-004: No `node has no providerID` errors in the CCM log after the repair
  ```
  kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'node has no providerID'
  ```
  **Expected**: `0` (no new occurrences after the providerID patch)

- [ ] AC-005: No `Failed to watch *v1.Service` errors in the CCM log after the RBAC fix
  ```
  kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'Failed to watch \*v1.Service'
  ```
  **Expected**: `0` (no new occurrences after the RBAC re-apply)

- [ ] AC-006: ELB has registered targets and serves traffic
  ```
  aws elb describe-load-balancers --load-balancer-names <ingress-ELB-name> \
    --query 'LoadBalancerDescriptions[0].Instances[].InstanceId' --output json
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://<ingress-ELB-DNS>/
  ```
  **Expected**: `Instances` is a non-empty list of `i-...`; `curl` returns a non-`000`/non-`52` HTTP status (`200`/`404`/`503` all acceptable)

## 4. Out of Scope
- No CCM version/arg change (004-5 `--v=4`, 004-9 `scheme: HTTPS` stay)
- No node IAM change (the `node_aws_ccm` policy is already sufficient)
- No instance tag change (004-6 stays)
- No `--aws-node-name` CCM flag change (the providerID fix is the standard approach; switching the node-name type is a workaround, not a fix)
- No Route53 / TLS termination (deferred)
- No cleanup of orphaned ELBs from prior cluster recreations (a known side-effect, not this bug)

## 5. Downstream Consumer
- **004-4-aws-cloud-controller-manager** — AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become fully verifiable: the ELB now has targets and serves traffic (AC-006)
- **007-app-frontend-ingress** — end-to-end `curl -H "Host: app.local" http://<ELB-DNS>/` + `/api/` routing becomes testable once the ELB serves traffic
- **005/006 (apps)** — the app pods are reachable through the Ingress once the ELB targets are registered
