# Spec: Re-apply Cluster Manifests on Control-Plane Recreation

**Feature Branch**: `004-10-reapply-manifests-on-recreation` | **Date**: 2026-09-15 | **Status**: Draft

## 1. Technical Scope & Infrastructure Contracts

- **Infrastructure Scope**: Terraform only — `null_resource` trigger maps (no AWS resource, IAM, or VPC change)
- **Kubernetes / Cluster Scope**: All cluster manifests applied via SSM Run Command — Flannel CNI, EBS CSI + ingress-nginx + `sdd-apps` ns, MySQL, app backend, app frontend + Ingress, AWS CCM
- **Target Services / Modules**: `terraform/environments/dev/main.tf` — six `null_resource` apply steps
- **Root Cause (confirmed via `kubectl get nodes` + `kubectl get pod -n kube-system`, post-004-9)**: The 004-9 apply **recreated the entire cluster** (new control plane `i-0786ed8f9c3d7fe77` launched `00:49:20`, new workers `00:49:33`; the prior `~00:00` instances were destroyed). But the six manifest-apply `null_resource`s have `triggers` maps that **do not include the control-plane instance ID**:
  ```
  apply_flannel_cni          triggers = { flannel_version, pod_cidr }
  apply_app_infrastructure   triggers = { ebs_csi_ref, ingress_ref, git_bootstrap }
  apply_mysql                triggers = { mysql_image }
  apply_app_backend          triggers = { backend_image }
  apply_app_frontend_ingress triggers = { frontend_image, ingress_host }
  apply_aws_ccm              triggers = { ccm_version, ccm_log_level }
  ```
  Terraform re-runs a `null_resource` provisioner **only when its `triggers` map changes**. The provisioner command string (which embeds `base64encode(file(...))` and the instance ID) is **not** part of the resource state — Terraform does not hash or compare it. So on a cluster recreation, every trigger was unchanged → **all six applies were silently skipped** → the new cluster has no CNI, no CCM, no ingress, no apps.
- **Observed failure**: `kubectl get nodes` → all 3 nodes `NotReady` (`KubeletNotReady: ... NetworkPluginNotReady ... cni plugin not initialized`); `kubectl get pod -n kube-system` → **no flannel pod**, coredns `Pending`, no CCM pod; ELB `aa1d0a483aa6e484e8a5a4c460e38dc7` has `Instances: []`; `curl` → `000`. The "green workflow" means `terraform apply` exited 0 (no errors), **not** that the cluster is healthy.
- **Note on 004-9**: the `scheme: HTTPS` CCM liveness-probe fix is correct, committed, and merged — it simply was never applied to the new cluster because `apply_aws_ccm` did not re-run. This spec makes that (and every other manifest) re-apply on recreation.

## 2. Infrastructure Contracts

### 2.1 `null_resource` Trigger Maps (Modify — `terraform/environments/dev/main.tf`)
- **Target**: the `triggers` block of each of the six apply `null_resource`s (lines ~88, ~171, ~256, ~333, ~410, ~495)
- **Change**: add the control-plane instance ID to each `triggers` map so a cluster recreation changes the trigger and re-runs the provisioner:
  ```hcl
  triggers = {
    # ...existing keys unchanged...
    instance_id = module.control_plane.control_plane_instance_id
  }
  ```
- **Why the instance ID**: it is the value that changes when the cluster is recreated. Adding it makes the trigger map a function of cluster identity, so any recreation (new instance ID) forces a re-apply of every manifest to the new control plane. Existing keys stay — they still re-trigger on their own version bumps.
- **All six resources, same one-line addition**:
  | Resource | Line | Existing triggers | Add |
  |---|---|---|---|
  | `apply_flannel_cni` | ~88 | `flannel_version`, `pod_cidr` | `instance_id` |
  | `apply_app_infrastructure` | ~171 | `ebs_csi_ref`, `ingress_ref`, `git_bootstrap` | `instance_id` |
  | `apply_mysql` | ~256 | `mysql_image` | `instance_id` |
  | `apply_app_backend` | ~333 | `backend_image` | `instance_id` |
  | `apply_app_frontend_ingress` | ~410 | `frontend_image`, `ingress_host` | `instance_id` |
  | `apply_aws_ccm` | ~495 | `ccm_version`, `ccm_log_level` | `instance_id` |

### 2.2 No Other Changes
- No new resource, no manifest change, no IAM change, no VPC change, no CCM arg/version change.
- The `depends_on` chains (flannel → app_infrastructure → mysql → backend → frontend_ingress → ccm) are unchanged — they already order the applies correctly; the bug is purely that they did not re-run at all.
- The 004-9 `scheme: HTTPS` CCM probe fix stays in `manifests/aws-ccm.yaml` (already merged).

## 3. Acceptance Criteria

All criteria are machine-verifiable. The `kubectl` commands run on the control plane via SSM (per the existing apply pattern) or from any host with `KUBECONFIG=/etc/kubernetes/admin.conf`.

- [ ] AC-001: Terraform syntax & formatting validation passes
  ```
  terraform fmt -check -recursive && terraform validate
  ```
  **Expected**: exit 0, no diff

- [ ] AC-002: Plan shows all six apply `null_resource`s will be replaced (trigger change)
  ```
  terraform plan -detailed-exitcode
  ```
  **Expected**: exit 2; plan shows `null_resource.apply_flannel_cni`, `apply_app_infrastructure`, `apply_mysql`, `apply_app_backend`, `apply_app_frontend_ingress`, `apply_aws_ccm` each as `will be replaced` (destroy + create), zero AWS resource create/destroy

- [ ] AC-003: Every apply `null_resource` trigger map contains the instance ID
  ```
  grep -cE '(^|[^a-zA-Z0-9_])instance_id[[:space:]]+=[[:space:]]+module\.control_plane\.control_plane_instance_id' terraform/environments/dev/main.tf
  ```
  **Expected**: `6` (one per apply `null_resource`; anchored to the standalone `instance_id` key, tolerates `terraform fmt` `=`-alignment)

- [ ] AC-004: After the next `terraform apply`, all nodes are Ready
  ```
  kubectl get nodes
  ```
  **Expected**: 3 nodes, all `Ready` (Flannel CNI applied → `NetworkReady=true`)

- [ ] AC-005: Flannel CNI DaemonSet is running on all nodes
  ```
  kubectl get ds -n kube-flannel kube-flannel-ds
  ```
  **Expected**: `DESIRED = READY = AVAILABLE = 3`

- [ ] AC-006: CCM pod is Ready and stable (004-9 probe fix now live)
  ```
  kubectl get pod -n kube-system -l app=aws-cloud-controller-manager
  ```
  **Expected**: `1/1 Running`, low/stable restart count; `kubectl get deploy -n kube-system aws-cloud-controller-manager -o yaml | grep -A6 livenessProbe` shows `scheme: HTTPS`

- [ ] AC-007: Ingress Service EXTERNAL-IP populated and ELB serves traffic
  ```
  kubectl get svc -n ingress-nginx ingress-nginx-controller
  ```
  **Expected**: EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`); `curl -s -o /dev/null -w '%{http_code}' http://<ELB-DNS>/` returns a non-`000`/non-`52` HTTP status

## 4. Out of Scope
- No CCM version/arg change (004-5 `--v=4`, 004-9 `scheme: HTTPS` stay)
- No IAM change (004-8 `elasticloadbalancing:*` wildcard stays)
- No instance tag change (004-6 stays)
- No manifest content change (all manifests stay as-is; only the Terraform triggers change)
- No `depends_on` reordering (the existing chain is correct)
- No Route53 / TLS termination (deferred)

## 5. Downstream Consumer
- **004-9-ccm-liveness-probe-scheme** — its `scheme: HTTPS` fix becomes live on the cluster once `apply_aws_ccm` re-runs (AC-006)
- **004-4-aws-cloud-controller-manager** — AC-003/004 (EXTERNAL-IP, Ingress ADDRESS) become verifiable once the CCM is applied and registers ELB targets (AC-007)
- **005/006/007 (apps + ingress)** — MySQL, backend, frontend, and Ingress objects are re-applied to the new cluster (AC-004/005), unblocking end-to-end routing
