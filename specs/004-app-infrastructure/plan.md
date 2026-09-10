# Architecture Delta: Application Infrastructure (EBS CSI + Ingress + Namespaces)

**Branch**: `004-app-infrastructure` | **Date**: 2026-09-09 | **Spec**: specs/004-app-infrastructure/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Add `aws_iam_role_policy.node_ebs_csi` (EBS volume-lifecycle actions) to the existing `sdd-k8s-platform-node-role` — the EBS CSI controller + node plugin use node instance-profile creds via IMDS (no IRSA) |
| `terraform/environments/dev/manifests/ebs-gp3-storageclass.yaml` | Create | `ebs-gp3` StorageClass manifest (provisioner `ebs.csi.aws.com`, gp3, 3000 IOPS, 125 MB/s, ext4, Retain, WaitForFirstConsumer, allowVolumeExpansion) — read + base64-encoded into the SSM command |
| `terraform/environments/dev/main.tf` | Modify | Add `null_resource.apply_app_infrastructure` (Flannel pattern): SSM-agent wait + bootstrap-instance-id gate (003-11) → `aws ssm send-command` to the control plane running `kubectl apply` for namespace → EBS CSI → StorageClass → ingress |

No new module. No new variables/outputs (the `control_plane_instance_id` output already exists from 003-2). The EBS IAM policy is added to the existing `cluster-plumbing` module (003-1) because the node role lives there.

## 2. Architecture Delta

The cluster goes from "Ready 3-node cluster with Flannel CNI" (003) to "workload-ready" (004): it can now run stateful workloads (EBS-backed PVCs) and expose them externally (ingress).

- **Before**: nodes have SSM + ECR + Parameter Store perms only. No storage driver, no ingress, no app namespace. A MySQL StatefulSet PVC would fail (no `ebs.csi.aws.com` provisioner).
- **After**:
  - **EBS CSI driver** (`release-1.65`) installed in-cluster → `ebs-csi-controller` Deployment + `ebs-csi-node` DaemonSet in `kube-system`.
  - **`ebs-gp3` StorageClass** → dynamic provisioning for PVCs (consumed by 005 MySQL).
  - **NGINX Ingress** (`controller-v1.15.1`) → `ingress-nginx` namespace, `ingress-nginx-controller` Deployment, `LoadBalancer` Service (public hostname), `IngressClass` `nginx` (default).
  - **`sdd-apps` namespace** → where 005 workloads land.
  - **Node role** gains EBS volume-lifecycle IAM actions.

**Why `null_resource` + SSM (not the `kubernetes` provider or SSH)**: the API server is private (no public IP) and the project uses SSM, not SSH. The CI runner has OIDC AWS creds; the control plane has the SSM agent + kubeconfig. So the runner sends `aws ssm send-command` and the control plane runs `kubectl apply`. This is the exact pattern 003-3 uses for Flannel — reusing the proven, real-AWS-verified mechanism (SSM-agent wait 003-4, bootstrap gate 003-11, KUBECONFIG 003-9, poll query 003-10).

**Apply order** (single SSM command, sequential): namespace → EBS CSI → StorageClass → ingress. The StorageClass is base64-encoded into the command to avoid JSON-escaping (003-6 gotcha).

## 3. Rollout Stages

1. **EBS node-role IAM (agent)** — add `aws_iam_role_policy.node_ebs_csi` to `cluster-plumbing/main.tf`.
2. **StorageClass manifest (agent)** — create `manifests/ebs-gp3-storageclass.yaml`.
3. **Apply resource (agent)** — add `null_resource.apply_app_infrastructure` to `dev/main.tf` (gate + SSM send-command + poll).
4. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate` (AC-001); `terraform plan -detailed-exitcode` (AC-002); `terraform state list | grep node_ebs_csi` (AC-008).
5. **End-to-end verification (CI, user-managed)** — apply runs; the gate blocks until the control plane is ready; the SSM command applies namespace → EBS CSI → StorageClass → ingress; AC-003 (CSI ready), AC-004 (StorageClass), AC-005 (ingress rollout), AC-006 (LB hostname), AC-007 (namespace) verified via SSM.

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `terraform plan -detailed-exitcode`
- **AC-003**: EBS CSI controller + node plugin ready (SSM: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=ebs-csi-controller -n kube-system --timeout=300s && ... -l app=ebs-csi-node ...`)
- **AC-004**: `ebs-gp3` StorageClass provisioner is `ebs.csi.aws.com` (SSM: `kubectl get storageclass ebs-gp3 -o jsonpath={.provisioner}`)
- **AC-005**: ingress controller rolled out (SSM: `kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s`)
- **AC-006**: ingress LB has an external hostname (SSM: `kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath={.status.loadBalancer.ingress[0].hostname}` matches `\.elb\.`)
- **AC-007**: `sdd-apps` namespace exists (SSM: `kubectl get namespace sdd-apps -o jsonpath={.metadata.name}`)
- **AC-008**: `terraform state list | grep -q 'aws_iam_role_policy.node_ebs_csi'`

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| EBS CSI controller can't create/attach volumes (no IAM) | `node_ebs_csi` policy grants the full volume-lifecycle action set to the node role; controller + node plugin use node instance-profile creds via IMDS |
| Ingress `LoadBalancer` Service takes minutes to provision an LB | AC-005 (rollout) and AC-006 (hostname) are separate; the LB hostname poll allows up to 300s |
| `kubectl apply -k` gitops URL with `?ref=` breaks inside the SSM `--parameters` JSON | The URL is single-quoted inside the double-quoted JSON string; the `?` and `=` are not JSON-special. Verified pattern from the user-provided install command |
| StorageClass YAML JSON-escaping in `--parameters` | Base64-encode the manifest file and `base64 -d` on the control plane (003-6 gotcha) |
| Apply races the control-plane bootstrap on a fresh apply | The bootstrap-instance-id gate (003-11) blocks until the param equals the current instance ID; on a persistent 003 cluster it returns immediately |
| `null_resource` re-runs on every apply (wasteful) | `triggers` are pinned refs (`release-1.65`, `controller-v1.15.1`); Terraform skips the provisioner when unchanged (idempotent) |
| Node role change requires instance restart to take effect | IAM instance-profile changes propagate to running instances within ~15 min (no restart needed); the EBS CSI pods start after the policy is attached in the same apply |
