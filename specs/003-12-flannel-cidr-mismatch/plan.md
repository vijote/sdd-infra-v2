# Architecture Delta: Flannel CNI CIDR Mismatch Fix

**Branch**: `003-12-flannel-cidr-mismatch` | **Date**: 2026-09-10 | **Spec**: specs/003-12-flannel-cidr-mismatch/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
|-----------|-----------|-------------------|
| `terraform/environments/dev/main.tf` | Modify | `null_resource.apply_flannel_cni`: (1) insert a `sed` step in the SSM command between the `curl` and `kubectl apply` to rewrite the stock manifest's `Network: 10.244.0.0/16` → `192.168.0.0/16`; (2) append a `kubectl -n kube-flannel rollout restart ds/kube-flannel-ds` step so flanneld re-reads the config; (3) add a `pod_cidr = "192.168.0.0/16"` trigger so the provisioner re-runs when the pod CIDR changes |

No new module, no new variables/outputs, no AWS resource changes. The fix is entirely within the existing Flannel `null_resource` (the same resource 003-3 created and 003-4/003-7/003-11 hardened).

## 2. Architecture Delta

The cluster's pod networking goes from "Flannel manifest applied but flanneld crash-looping" to "Flannel CNI functional".

- **Before**: `kubeadm init` assigns node PodCIDRs from `podSubnet: 192.168.0.0/16` (`control-plane/bootstrap.sh` `POD_CIDR`). The stock Flannel manifest's `net-conf.json` hardcodes `Network: 10.244.0.0/16`. Flannel's kube subnet manager requires each node's PodCIDR to fall *inside* its `Network` CIDR; `192.168.0.0/24` ∉ `10.244.0.0/16` → flanneld fails to acquire its lease → crash loop → no `/run/flannel/subnet.env` → no pod IPs → all networked pods stuck in `ContainerCreating` (CoreDNS, ingress, EBS CSI).
- **After**: the `net-conf.json` `Network` is `192.168.0.0/16` (matching the kubeadm podSubnet). flanneld acquires its lease, writes `subnet.env`, and pods get pod IPs. CoreDNS and the 004 workloads (ingress, EBS CSI) become Ready.

**Why sed the manifest (not patch the ConfigMap inline)**: the stock manifest is curled to `/tmp/kube-flannel.yml` and applied as a file. A `sed -i` on that file before `kubectl apply` is the simplest, most robust way to change the CIDR — it avoids the 003-6 JSON-escaping gotcha of embedding a `kubectl patch` with a JSON body inside the SSM `--parameters` value. The sed pattern is verified against the live cluster's ConfigMap dump (`"Network": "10.244.0.0/16"`).

**Why a daemonset restart**: on a *fresh* apply the sed'd manifest is applied for the first time, so no restart is strictly needed. But on a *persistent* cluster (like the current one, where the bad ConfigMap already exists), `kubectl apply` of the sed'd manifest updates the ConfigMap, and flanneld must be restarted to re-read it. The `rollout restart` makes the fix work in both cases and is idempotent.

**Why a `pod_cidr` trigger**: the CIDR is currently hardcoded in the sed command. Adding it as a trigger means if the pod CIDR ever changes, the provisioner re-runs (and the sed would need updating — a visible, intentional coupling).

## 3. Rollout Stages

1. **Modify the SSM command (agent)** — in `dev/main.tf` `apply_flannel_cni`: insert the sed step, append the rollout restart, add the `pod_cidr` trigger.
2. **Static verification (CI)** — `terraform fmt -check -recursive && terraform validate` (AC-001); `terraform plan -detailed-exitcode` (AC-002).
3. **End-to-end verification (CI, user-managed)** — the apply re-runs (trigger change); the sed'd manifest is applied; the daemonset restarts; AC-003 (ConfigMap CIDR), AC-004 (daemonset rollout), AC-005 (CoreDNS Ready) verified via SSM.

## 4. Verification Gates (executed in GitHub Actions CI, never locally)

- **AC-001**: `terraform fmt -check -recursive && terraform validate`
- **AC-002**: `terraform plan -detailed-exitcode`
- **AC-003**: Flannel `net-conf.json` Network CIDR is `192.168.0.0/16` (SSM: `kubectl -n kube-flannel get cm kube-flannel-cfg -o jsonpath={.data}` contains `192.168.0.0/16`)
- **AC-004**: Flannel daemonset fully rolled out (SSM: `kubectl -n kube-flannel rollout status ds/kube-flannel-ds --timeout=300s`)
- **AC-005**: CoreDNS pods Ready (SSM: `kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=300s`) — proves pods get pod IPs, closing the gap 003-11 missed

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| sed pattern doesn't match (manifest format differs) | Pattern verified against the live cluster's ConfigMap dump (`"Network": "10.244.0.0/16"`); AC-003 catches a no-op sed (ConfigMap would still show `10.244.0.0/16`) |
| sed matches an unintended occurrence of `10.244.0.0/16` | The stock v0.24.0 manifest contains the CIDR only in `net-conf.json`; the `g` flag is safe |
| Daemonset restart causes a brief CNI blip | Idempotent and safe — flanneld re-reads the config; on a fresh apply the restart is a no-op (pods already have the right config) |
| Trigger change forces a re-run on the next apply | Intended — the re-run is what applies the fix to the persistent cluster |
| CoreDNS still not Ready after Flannel fix (unrelated issue) | AC-005 isolates the CNI fix; if CoreDNS is still stuck, the cause is elsewhere (e.g. image pull) and would surface in the pod events |
