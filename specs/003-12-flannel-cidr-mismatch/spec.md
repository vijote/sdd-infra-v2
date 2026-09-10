# Spec: Flannel CNI CIDR Mismatch Fix

**Feature Branch**: `003-12-flannel-cidr-mismatch` | **Date**: 2026-09-10 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: none (no new AWS resources)
- **Kubernetes / Cluster Scope**: Flannel CNI (`kube-flannel-cfg` ConfigMap, `kube-flannel-ds` DaemonSet) / CoreDNS readiness
- **Target Services / Modules**: Flannel CNI v0.24.0 (pod networking)
- **Security & CI/CD**: all `kubectl` via SSM Run Command on the control plane (Flannel pattern, 003-3/003-11)

> **Root cause**: `kubeadm init` assigns node PodCIDRs from `podSubnet: 192.168.0.0/16` (`control-plane/bootstrap.sh` `POD_CIDR`). The stock Flannel manifest's `net-conf.json` hardcodes `Network: 10.244.0.0/16`. Flannel's kube subnet manager requires each node's PodCIDR to fall *inside* its `Network` CIDR; `192.168.0.0/24` ∉ `10.244.0.0/16` → flanneld fails to acquire its lease → crash loop → no `/run/flannel/subnet.env` → no pod IPs → all networked pods stuck in `ContainerCreating` (CoreDNS, ingress). 003-11 verified the `kubectl apply` succeeded but never verified pods actually get IPs, so this slipped through.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# Modify the existing null_resource.apply_flannel_cni (dev/main.tf) SSM command.
# After curling the stock manifest, sed the Network CIDR to match the kubeadm podSubnet,
# apply, then restart the daemonset so flanneld re-reads the config:
#   curl -sSL $FLANNEL_URL -o /tmp/kube-flannel.yml
#   sed -i 's/10\.244\.0\.0\/16/192.168.0.0\/16/g' /tmp/kube-flannel.yml
#   KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /tmp/kube-flannel.yml
#   KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout restart ds/kube-flannel-ds
# Add a trigger so the provisioner re-runs when the pod CIDR changes:
#   triggers = { flannel_version = local.flannel_version, pod_cidr = "192.168.0.0/16" }
```

### 1.2 Kubernetes Manifest / Helm Values Contracts
- **`kube-flannel-cfg` ConfigMap** `net-conf.json`: `Network: 192.168.0.0/16`, `Backend.Type: vxlan` (was `10.244.0.0/16`).
- **`kube-flannel-ds` DaemonSet**: restarted after the ConfigMap change so flanneld re-reads `net-conf.json`.

### 1.3 Data & Storage Contracts
- N/A (no storage scope).

### 1.4 Network & Security Contracts
- **Flannel CNI**: VXLAN backend, `Network: 192.168.0.0/16` (must contain the kubeadm-assigned node PodCIDRs `192.168.0.0/24`, `192.168.1.0/24`, `192.168.2.0/24`).
- **No new security groups / IAM** (reuses the existing control-plane SSM channel).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — no public API endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-005 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Flannel `net-conf.json` Network CIDR is `192.168.0.0/16`
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel get cm kube-flannel-cfg -o jsonpath={.data}"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'StandardOutputContent' --output text | grep -q '192.168.0.0/16'
  ```
- [ ] AC-004: Flannel daemonset is fully rolled out (no crash loop)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: CoreDNS pods are Ready (proves pods get pod IPs — the gap 003-11 missed)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=300s"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `003-2-control-plane` (kubeadm podSubnet `192.168.0.0/16`), `003-3-worker-nodes` (3-node cluster), `003-11` (bootstrap-instance-id gate).
- **Downstream Consumer**: `004-app-infrastructure` (ingress + EBS CSI pods need working pod networking).
- **Fix mechanism**: sed the Network CIDR in the pinned v0.24.0 stock manifest before apply (avoids the 003-6 JSON-escaping gotcha of patching the ConfigMap inline).
- **Idempotency**: re-runnable; the daemonset restart is safe (flanneld re-reads the config).
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
