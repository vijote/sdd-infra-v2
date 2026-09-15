# Architecture Delta: Re-apply Cluster Manifests on Control-Plane Recreation

**Branch**: `004-10-reapply-manifests-on-recreation` | **Date**: 2026-09-15 | **Spec**: [specs/004-10-reapply-manifests-on-recreation/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Change |
|------|-----------|--------|
| `terraform/environments/dev/main.tf` | Modify | Add `instance_id = module.control_plane.control_plane_instance_id` to the `triggers` map of each of the six apply `null_resource`s: `apply_flannel_cni` (~line 88), `apply_app_infrastructure` (~171), `apply_mysql` (~256), `apply_app_backend` (~333), `apply_app_frontend_ingress` (~410), `apply_aws_ccm` (~495). Existing trigger keys unchanged. |

## 2. Architectural Boundaries & Dependency Flow

- **Terraform Layer**: the six `null_resource` apply steps form a `depends_on` chain (flannel → app_infrastructure → mysql → backend → frontend_ingress → ccm) that already orders the applies correctly. The bug is not ordering — it is that the chain **never re-ran** after a cluster recreation, because `triggers` (the only thing Terraform compares for `null_resource` re-runs) contained only version strings, not cluster identity.
- **Cluster Identity**: `module.control_plane.control_plane_instance_id` is the value that changes on every recreation. Adding it to `triggers` makes each apply a function of cluster identity: new instance ID → trigger change → provisioner re-runs → manifests re-applied to the new control plane.
- **No graph change**: no new resource, no `depends_on` change, no manifest/IAM/VPC change. The provisioner command strings are untouched.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` → all six `null_resource`s show `will be replaced` (trigger change) → provisioners re-run in `depends_on` order. Each waits for the control plane's SSM agent + the per-run bootstrap signal (existing logic, unchanged), then re-applies its manifest via SSM Run Command.
2. **Stage 2 - CNI first**: `apply_flannel_cni` re-applies Flannel → `kube-flannel-ds` DaemonSet schedules on all 3 nodes → `NetworkReady=true` → nodes flip `NotReady` → `Ready`.
3. **Stage 3 - Addons & apps**: `apply_app_infrastructure` (EBS CSI, ingress-nginx, `sdd-apps` ns) → `apply_mysql` → `apply_app_backend` → `apply_app_frontend_ingress` re-apply in order; pods now schedule (nodes Ready).
4. **Stage 4 - CCM + ELB**: `apply_aws_ccm` re-applies the CCM manifest (now carrying 004-9's `scheme: HTTPS` probe) + the public-subnet Service annotation → CCM becomes leader, registers ELB targets → Ingress Service EXTERNAL-IP populates, ELB serves traffic.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **Plan Delta**: `terraform plan -detailed-exitcode` → exit 2; all six `null_resource`s `will be replaced`, zero AWS resource create/destroy
- **Trigger Content**: `grep -cE '(^|[^a-zA-Z0-9_])instance_id[[:space:]]+=[[:space:]]+module\.control_plane\.control_plane_instance_id' terraform/environments/dev/main.tf` → `6`
- **Node Readiness**: `kubectl get nodes` → 3 nodes, all `Ready`
- **CNI Health**: `kubectl get ds -n kube-flannel kube-flannel-ds` → `DESIRED=READY=AVAILABLE=3`
- **CCM Health**: `kubectl get pod -n kube-system -l app=aws-cloud-controller-manager` → `1/1 Running`, stable restart count; `livenessProbe` shows `scheme: HTTPS`
- **Service Endpoint**: `kubectl get svc -n ingress-nginx ingress-nginx-controller` → EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com`; `curl` to the ELB returns a non-`000`/non-`52` HTTP status

## 5. Key Decisions

- **Instance ID in triggers, not a `depends_on` on the instance**: a `depends_on` on `aws_instance` would only re-run the apply when the instance *resource* changes in the same apply graph; the `triggers` approach is the documented `null_resource` re-run mechanism and also covers out-of-band recreation. It matches the existing pattern (version strings in `triggers`).
- **All six, not just the broken ones**: every apply step has the identical latent bug. Fixing only `apply_flannel_cni` would leave CCM/ingress/apps missing on the next recreation. One consistent rule: *any manifest applied to the cluster must re-apply when the cluster is recreated*.
- **Existing trigger keys stay**: version keys (`flannel_version`, `ccm_version`, `mysql_image`, ...) still re-trigger on their own bumps; `instance_id` is additive, not a replacement.
- **No manifest content change**: 004-9's `scheme: HTTPS` fix is already merged in `manifests/aws-ccm.yaml`; this spec only makes the apply actually run.
