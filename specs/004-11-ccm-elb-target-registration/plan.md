# Architecture Delta: CCM ELB Target Registration (Node providerID + RBAC)

**Branch**: `004-11-ccm-elb-target-registration` | **Date**: 2026-09-15 | **Spec**: [specs/004-11-ccm-elb-target-registration/spec.md](spec.md)

## 1. File Impact Matrix

| File | Operation | Change |
|------|-----------|--------|
| `terraform/environments/dev/manifests/aws-ccm.yaml` | Modify | CCM ClusterRole: add `get` + `watch` to the `services` and `services/status` rules (lines ~22–49). |
| `terraform/modules/control-plane/bootstrap.sh` | Modify | Fetch AZ via IMDSv2 (extend existing fail-fast guard); configure `KUBELET_EXTRA_ARGS` in `/etc/sysconfig/kubelet` and `kubeletExtraArgs.provider-id: aws://${AZ}/${INSTANCE_ID}` in `kubeadm-config.yaml`. |
| `terraform/modules/worker-nodes/bootstrap.sh` | Modify | Add IMDSv2 fetch block (token + `INSTANCE_ID` + `AZ`, fail-fast guard); configure `KUBELET_EXTRA_ARGS` in `/etc/sysconfig/kubelet` (since `kubeadm join` has no `--provider-id` CLI flag). |
| `terraform/environments/dev/main.tf` | Modify | New `null_resource.set_node_provider_ids` (SSM Run Command on the control plane: map each node's InternalIP → instance ID + AZ via `aws ec2 describe-instances`, then `kubectl patch node ... spec.providerID`); chained before `apply_aws_ccm`; triggers = `instance_id` + `provider_id_ref = "1"`. |

## 2. Architectural Boundaries & Dependency Flow

- **Node Identity Layer**: `spec.providerID` (`aws:///<az>/<id>`) is the contract between kubelet (set at init/join) and the CCM (consumed to map nodes → EC2 instances). The CCM's default `--aws-node-name=NodeNameProviderID` requires it; without it, ELB target registration is impossible.
- **RBAC Layer**: the CCM Service informer needs `get`/`list`/`watch` on `services` + `services/status` to maintain the ELB target set; the current role has only `list` (+mutating verbs) → `Failed to watch *v1.Service`.
- **Two repair paths, one contract**:
  - *Forward*: bootstrap scripts (control plane + workers) set `providerID` at `kubeadm init`/`join` time — applies to every future cluster recreation.
  - *In-place*: `set_node_provider_ids` patches the **current** cluster's nodes via SSM — no `terraform destroy` needed. Idempotent (re-patching the same value is a no-op); re-runs on recreation via the `instance_id` trigger (004-10 pattern).
- **No graph change beyond the new resource**: `set_node_provider_ids` slots into the existing `depends_on` chain between `apply_app_frontend_ingress` and `apply_aws_ccm` (CCM must start after nodes have providerIDs). No IAM/VPC/SG change.

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` → `set_node_provider_ids` re-runs (new resource) → SSM patches `spec.providerID` on all 3 nodes → `apply_aws_ccm` re-runs (manifest changed: RBAC) → CCM restarts with the corrected ClusterRole.
2. **Stage 2 - CCM reconcile**: with `providerID` set, the CCM resolves each node to its EC2 instance; with `watch`/`get` on services, the Service informer stays healthy. `EnsureLoadBalancer` registers the node instances as ELB targets.
3. **Stage 3 - ELB serves**: `aws elb describe-load-balancers` shows `Instances: [i-...]`; `curl` to the ELB returns a real HTTP code (not `000`/`52`).
4. **Stage 4 - Future recreations**: bootstrap scripts now embed `providerID` at init/join, so recreated clusters are correct from first boot (the in-place repair remains as a safety net).

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate`
- **RBAC**: `kubectl auth can-i watch services --as=system:serviceaccount:kube-system:aws-cloud-controller-manager` → `yes`; same for `get services`
- **Node Identity**: `kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.providerID}{"\n"}{end}'` → 3 lines, each `aws://us-east-1a/i-...`
- **CCM Log (providerID)**: `kubectl logs -n kube-system -l app=aws-cloud-controller-manager --tail=200 | grep -c 'node has no providerID'` → `0` new
- **CCM Log (RBAC)**: `kubectl logs ... | grep -c 'Failed to watch \*v1.Service'` → `0` new
- **ELB Targets**: `aws elb describe-load-balancers --load-balancer-names <ingress-ELB> --query '...Instances[].InstanceId'` → non-empty; `curl` to the ELB → non-`000`/non-`52`

## 5. Key Decisions

- **Set `providerID` at the source (init/join), not via a CCM flag**: switching `--aws-node-name` to a name-type that matches the current node names is a workaround that breaks the standard `aws:///<az>/<id>` contract; the providerID is the upstream-recommended approach and also fixes node-controller address metadata.
- **In-place repair as a `null_resource`, not a manual step**: the current cluster's nodes already booted without providerIDs; a one-time SSM patch (idempotent, trigger-gated) heals them without a `terraform destroy`/recreation. It also self-heals any future cluster where the bootstrap path regresses.
- **Repair runs before the CCM apply**: `apply_aws_ccm` gains `depends_on = [null_resource.set_node_provider_ids, ...]` so the CCM reconciles against nodes that already have providerIDs (avoids a reconcile window with the old error).
- **RBAC fix is additive**: `get`/`watch` added to existing rules; no other rule changes. Matches the upstream `cloud-provider-aws` RBAC.
- **No IAM change**: the `node_aws_ccm` policy already grants `ec2:Describe*` + `ec2:RegisterInstancesWithLoadBalancer` — the AWS side was never the problem.
