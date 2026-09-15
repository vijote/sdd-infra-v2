# Execution Graph (DAG): Re-apply Cluster Manifests on Control-Plane Recreation

**Input**: Design documents from `/specs/004-10-reapply-manifests-on-recreation/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 7 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Terraform] In `terraform/environments/dev/main.tf`: add `instance_id = module.control_plane.control_plane_instance_id` to the `triggers` map of each of the six apply `null_resource`s — `apply_flannel_cni` (~line 88), `apply_app_infrastructure` (~171), `apply_mysql` (~256), `apply_app_backend` (~333), `apply_app_frontend_ingress` (~410), `apply_aws_ccm` (~495) — because Terraform re-runs a `null_resource` provisioner ONLY when its `triggers` map changes, and the provisioner command string (base64encode(file(...)) + instance ID) is NOT part of resource state; the 004-9 apply recreated the cluster (new control plane i-0786ed8f9c3d7fe77) with unchanged version triggers, so all six applies were silently skipped → new cluster has no CNI (all nodes NotReady: `cni plugin not initialized`), no CCM (ELB `Instances: []`, curl 000), no ingress, no apps; adding the instance ID makes each apply a function of cluster identity so any recreation re-applies every manifest; existing trigger keys (flannel_version, pod_cidr, ebs_csi_ref, ingress_ref, git_bootstrap, mysql_image, backend_image, frontend_image, ingress_host, ccm_version, ccm_log_level) stay unchanged

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T002 [Stage 2: Verify] AC-001: `terraform fmt -check -recursive && terraform validate` — exit 0, no diff (Depends on T001)
- [ ] T003 [Stage 2: Verify] AC-002: `terraform plan -detailed-exitcode` — exit 2; plan shows all six `null_resource`s (`apply_flannel_cni`, `apply_app_infrastructure`, `apply_mysql`, `apply_app_backend`, `apply_app_frontend_ingress`, `apply_aws_ccm`) as `will be replaced`, zero AWS resource create/destroy (Depends on T001)
- [ ] T004 [Stage 2: Verify] AC-003: `grep -cE '(^|[^a-zA-Z0-9_])instance_id[[:space:]]+=[[:space:]]+module\.control_plane\.control_plane_instance_id' terraform/environments/dev/main.tf` returns `6` (anchored to the standalone `instance_id` key; tolerates `terraform fmt` `=`-alignment) (Depends on T001)
- [ ] T005 [Stage 2: Verify] AC-004: after the next `terraform-apply` run (all six provisioners re-run in depends_on order) — `kubectl get nodes` shows 3 nodes, all `Ready` (Flannel CNI applied → NetworkReady=true) (Depends on T001)
- [ ] T006 [Stage 2: Verify] AC-005: `kubectl get ds -n kube-flannel kube-flannel-ds` shows `DESIRED=READY=AVAILABLE=3` (Depends on T001)
- [ ] T007 [Stage 2: Verify] AC-006: `kubectl get pod -n kube-system -l app=aws-cloud-controller-manager` shows `1/1 Running` with low/stable restart count + `kubectl get deploy -n kube-system aws-cloud-controller-manager -o yaml | grep -A6 livenessProbe` shows `scheme: HTTPS` (004-9 fix now live on the cluster) (Depends on T001)
- [ ] T008 [Stage 2: Verify] AC-007: `kubectl get svc -n ingress-nginx ingress-nginx-controller` shows EXTERNAL-IP = `*.elb.us-east-1.amazonaws.com` (not `<pending>`) + `curl -s -o /dev/null -w '%{http_code}' http://<ELB-DNS>/` returns a non-`000`/non-`52` HTTP status (ELB serves traffic) — 004-4's previously-blocked ACs (Depends on T001)
