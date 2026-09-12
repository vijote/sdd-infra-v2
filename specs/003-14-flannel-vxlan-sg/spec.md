# Spec: Flannel VXLAN Security Group Rules (Cross-Node Pod Networking)

**Feature Branch**: `003-14-flannel-vxlan-sg` | **Date**: 2026-09-12 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: 2 security group ingress rule additions (no new resources, no instance replacement)
- **Kubernetes / Cluster Scope**: none (Flannel is already deployed; the tunnel starts working as soon as the SG rules exist)
- **Target Services / Modules**: `aws_security_group.control_plane` + `aws_security_group.worker` in `terraform/modules/cluster-plumbing/main.tf`
- **Security & CI/CD**: static Terraform checks in CI; runtime verification via SSM Run Command on the control plane

> **Root cause**: Flannel (per-node pod subnets) tunnels cross-node pod traffic with **VXLAN (UDP 8472)** between node IPs, plus a **Flannel API (TCP 4240)** channel. Neither SG allows these — `control_plane` ingress is only 6443/2379-2380/22, `worker` ingress only 10250/30000-32767/22. Cross-node pod→pod packets are dropped at the receiving node's SG. Verified 2026-09-12: a busybox pod on a worker cannot reach the CoreDNS pod IP on the control plane (`connection timed out; no servers could be reached`), while node-level `curl`/`getent` to the EC2 API succeed. Consequence: the EBS CSI controller pod (on a worker) cannot resolve `ec2.us-east-1.amazonaws.com` → `CreateVolume` times out (`context deadline exceeded`) → 005 PVC `mysql-data-mysql-0` stuck `Pending`. Flannel pods show Ready because readiness only reflects subnet acquisition (via the API server, port 6443 — allowed), not tunnel health.

### 1.1 Terraform / HCL Resource Contracts

```hcl
# terraform/modules/cluster-plumbing/main.tf — add to BOTH aws_security_group.control_plane
# and aws_security_group.worker:
ingress {
  description = "Flannel VXLAN tunnel"
  from_port   = 8472
  to_port     = 8472
  protocol    = "udp"
  cidr_blocks = [var.vpc_cidr]
}

ingress {
  description = "Flannel API"
  from_port   = 4240
  to_port     = 4240
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr]
}
```

No other file changes. SG ingress rules are updatable in place — `terraform apply` modifies the existing SGs; no instance replacement, no cluster rebuild, no Flannel restart (VXLAN packets flow as soon as the rules exist).

### 1.2 Kubernetes Manifest / Helm Values Contracts
- N/A (no manifest changes; the existing Flannel DaemonSet + CoreDNS become functional across nodes).

### 1.3 Data & Storage Contracts
- N/A. Downstream effect: the 005 PVC `mysql-data-mysql-0` (currently `Pending`) should transition to `Bound` once the EBS CSI controller can resolve the EC2 API endpoint.

### 1.4 Network & Security Contracts
- **UDP 8472** (Flannel VXLAN) — node-to-node, scoped to `var.vpc_cidr` (10.0.0.0/16) only; not exposed to the internet.
- **TCP 4240** (Flannel API) — node-to-node, scoped to `var.vpc_cidr`.
- Both rules are symmetric (added to both SGs) because traffic flows in both directions (worker↔control-plane).

## 2. Technical Acceptance Criteria

All criteria MUST be machine-verifiable in CI/CD. AC-001–AC-002 are static (existing `terraform-apply.yml` job). AC-003–AC-005 execute **on the control plane via SSM** — no public endpoint, no kubeconfig in CI. Per P5/P6, AC-003–AC-005 are **user-managed verification**.

- [ ] AC-001: Terraform syntax and formatting valid (`terraform fmt -check -recursive && terraform validate`)
- [ ] AC-002: Terraform plan generates expected resources (`terraform plan -detailed-exitcode`)
- [ ] AC-003: Both SGs contain the VXLAN + Flannel API ingress rules
  ```bash
  for SG in sdd-k8s-control-plane sdd-k8s-worker; do
    aws ec2 describe-security-groups --filters "Key=group-name,Values=$SG" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==`8472` || FromPort==`4240`].{port:FromPort,proto:IpProtocol}" \
      --output json
  done
  ```
  (Each SG must show both `8472/udp` and `4240/tcp`.)
- [ ] AC-004: Cross-node pod→pod DNS works — a pod (scheduled on a worker; control plane is `NoSchedule`) resolves a cluster name via CoreDNS (running on the control plane)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl run dnstest --image=busybox:1.36 --restart=Never --command -- nslookup kubernetes.default", "sleep 25", "KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs dnstest", "KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete pod dnstest --now --ignore-not-found"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 30); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```
- [ ] AC-005: 005 PVC bound (EBS CSI controller can now reach the EC2 API)
  ```bash
  IID=$(terraform output -raw control_plane_instance_id)
  CID=$(aws ssm send-command --instance-ids $IID --document-name AWS-RunShellScript \
    --parameters 'commands=["KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pvc mysql-data-mysql-0 -n sdd-apps -o jsonpath='\''{.status.phase}'\''"]' \
    --query 'Command.CommandId' --output text)
  for i in $(seq 1 60); do
    S=$(aws ssm get-command-invocation --command-id $CID --instance-id $IID --query 'CommandInvocation.Status || Status' --output text)
    [ "$S" = "Success" ] && break; sleep 10
  done
  [ "$S" = "Success" ]
  ```

## 3. Assumptions & Technical Constraints
- **Upstream Dependencies**: `003-1-cluster-plumbing` (the SGs being fixed), `003-12-flannel-cidr-mismatch` (Flannel subnets correct), `005-mysql-statefulset` (AC-005's PVC exists and is `Pending`).
- **Downstream Consumer**: `005-mysql-statefulset` (PVC binding → MySQL pod scheduling → readiness), and any future cross-node pod traffic (backend→MySQL Service in a later spec).
- **In-place change**: SG ingress rules update without replacement; no Flannel restart, no pod restart required. The EBS CSI external-provisioner retries automatically (observed ~45s interval), so the PVC binds without re-applying 005.
- **Scope**: rules are scoped to `var.vpc_cidr` (10.0.0.0/16) — no internet exposure.
- **Testing Policy**: No unit or E2E test generation — validation via direct AWS CLI + SSM checks in CI/CD.
- **Tooling**: Terraform >= 1.5.0, AWS provider >= 5.0.0.
