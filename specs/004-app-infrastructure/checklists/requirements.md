# Technical Quality Checklist: Application Infrastructure (EBS CSI + Ingress + Namespaces)

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-09
**Feature**: [Application Infrastructure](../spec.md)

## 1. Technical Contract Completeness
- [x] CHK001 Are all Terraform resource contracts (EBS node-role policy, `null_resource.apply_app_infrastructure`) explicitly declared with exact actions, triggers, and provisioner interpreter?
- [x] CHK002 Is the EBS CSI driver pinned to an exact ref (`release-1.65`) and the install command explicit (`kubectl apply -k` gitops overlay)?
- [x] CHK003 Is the NGINX Ingress controller pinned to an exact tag (`controller-v1.15.1`) with the static cloud manifest URL explicit?
- [x] CHK004 Is the `ebs-gp3` StorageClass contract explicit (provisioner `ebs.csi.aws.com`, gp3, 3000 IOPS, 125 MB/s, ext4, Retain, WaitForFirstConsumer, allowVolumeExpansion)?
- [x] CHK005 Is the `sdd-apps` namespace contract explicit?
- [~] CHK006 Are Helm chart dependencies and `values.yaml` schemas specified? — N/A (no Helm scope; static manifests + gitops overlay)

## 2. Infrastructure & Security Hygiene
- [x] CHK007 Is EBS pod access via node-role IAM (instance profile via IMDS), NOT IRSA (kubeadm has no OIDC provider)?
- [x] CHK008 Are the EBS IAM actions scoped to volume lifecycle (Create/Delete/Attach/Detach/Describe/Tags/Snapshots/Modify)?
- [x] CHK009 Does CI verify via SSM only (no public API endpoint, no kubeconfig in CI)?
- [x] CHK010 Is the apply order explicit (namespace → EBS CSI → StorageClass → ingress)?
- [x] CHK011 Is the apply idempotent and version-controlled (re-runnable `null_resource`, re-triggers only on pinned-version change)?
- [x] CHK012 Is the bootstrap-instance-id gate reused (003-11) so the apply blocks until the control plane is ready?

## 3. Machine-Verifiable Acceptance Gates
- [x] CHK013 Does every acceptance criterion map directly to an executable CLI command?
- [x] CHK014 Are all contract requirements quantified (pinned refs, IOPS, throughput, timeouts)?
- [x] CHK015 Is the AC ordering explicit (CSI ready → StorageClass → ingress rollout → LB hostname → namespace → IAM policy)?

## Notes
- `[x]` = requirement met for this phase. `[~]` = not applicable to this phase (out of scope).
- cert-manager + Let's Encrypt TLS is deferred to `004-1-cert-manager` (out of scope here).
- Reviewer marks `[x]` when the technical design meets architecture and security standards.
- `/speckit-implement` enforces that acceptance checks pass via automated commands.
