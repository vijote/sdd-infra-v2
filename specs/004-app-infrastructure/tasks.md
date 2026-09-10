# Execution Graph (DAG): Application Infrastructure (EBS CSI + Ingress + Namespaces)

**Input**: Design documents from `/specs/004-app-infrastructure/`
**Prerequisites**: plan.md (File Impact Matrix & Rollout Stages), spec.md (Contracts & Acceptance Criteria)
**Estimated Duration**: ~10 min (agent file edits) + CI verification

---

## Stage 1: Implementation (Terraform + Manifest)

- [x] T001 [Stage 1: IAM] In `terraform/modules/cluster-plumbing/main.tf`: add `aws_iam_role_policy "node_ebs_csi"` (name `sdd-k8s-platform-node-ebs-csi`, `role = aws_iam_role.node.id`) granting the EBS volume-lifecycle actions (`ec2:CreateVolume`, `ec2:DeleteVolume`, `ec2:AttachVolume`, `ec2:DetachVolume`, `ec2:CreateTags`, `ec2:DeleteTags`, `ec2:DescribeVolumes`, `ec2:DescribeTags`, `ec2:DescribeInstances`, `ec2:DescribeSnapshots`, `ec2:ModifyVolume`) on `Resource = "*"`. The EBS CSI controller + node plugin use the node instance-profile creds via IMDS (no IRSA).
- [x] T002 [Stage 1: StorageClass] Create `terraform/environments/dev/manifests/ebs-gp3-storageclass.yaml` with the `ebs-gp3` StorageClass: `provisioner: ebs.csi.aws.com`, `parameters` (`type: gp3`, `iops: "3000"`, `throughput: "125"`, `fsType: ext4`), `reclaimPolicy: Retain`, `allowVolumeExpansion: true`, `volumeBindingMode: WaitForFirstConsumer`.
- [x] T003 [Stage 1: Apply] In `terraform/environments/dev/main.tf`: add `null_resource "apply_app_infrastructure"` with `depends_on = [module.worker_nodes]` and `triggers = { ebs_csi_ref = "release-1.65", ingress_ref = "controller-v1.15.1" }`. Its `local-exec` provisioner (`interpreter = ["/bin/bash", "-c"]`) must: (1) wait for the control plane's SSM agent to register (30×10s poll of `aws ssm describe-instance-information`), (2) gate on `/sdd-k8s-platform/kubeadm-bootstrap-instance-id` equaling `$INSTANCE_ID` (60×10s poll, 003-11 pattern), (3) `aws ssm send-command` to the control plane running, in order: `kubectl create namespace sdd-apps --dry-run=client -o yaml | kubectl apply -f -`, `kubectl apply -k 'github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.65'`, `echo '<base64 of manifests/ebs-gp3-storageclass.yaml>' | base64 -d | kubectl apply -f -`, `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml` — each prefixed with `KUBECONFIG=/etc/kubernetes/admin.conf` (003-9) — then (4) poll `aws ssm get-command-invocation` with `--query 'CommandInvocation.Status || Status'` (003-10) until `Success`. (Depends on T001, T002)

## Stage 2: Verification (CI-only)

- [ ] T004 [Stage 2: Static] AC-001: `terraform fmt -check -recursive && terraform validate` (Depends on T003)
- [ ] T005 [Stage 2: Plan] AC-002: `terraform plan -detailed-exitcode` exits 0 (Depends on T003)
- [ ] T006 [Stage 2: Static] AC-008: `terraform state list | grep -q 'aws_iam_role_policy.node_ebs_csi'` (Depends on T001)
- [ ] T007 [Stage 2: E2E] AC-003: EBS CSI controller + node plugin ready (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=ebs-csi-controller -n kube-system --timeout=300s && KUBECONFIG=/etc/kubernetes/admin.conf kubectl wait --for=condition=Ready pod -l app=ebs-csi-node -n kube-system --timeout=300s`) (Depends on T003)
- [ ] T008 [Stage 2: E2E] AC-004: `ebs-gp3` StorageClass provisioner is `ebs.csi.aws.com` (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get storageclass ebs-gp3 -o jsonpath={.provisioner}` returns `ebs.csi.aws.com`) (Depends on T003)
- [ ] T009 [Stage 2: E2E] AC-005: ingress controller rolled out (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s`) (Depends on T003)
- [ ] T010 [Stage 2: E2E] AC-006: ingress LB has an external hostname (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath={.status.loadBalancer.ingress[0].hostname}` matches `\.elb\.`) (Depends on T003)
- [ ] T011 [Stage 2: E2E] AC-007: `sdd-apps` namespace exists (SSM Run Command on control plane: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl get namespace sdd-apps -o jsonpath={.metadata.name}` returns `sdd-apps`) (Depends on T003)

---

## Parallelization Notes

- T001 (IAM) and T002 (StorageClass manifest) are independent file edits and can run in parallel.
- T003 (apply resource) depends on both T001 and T002 (the `null_resource` references the StorageClass manifest and the node role must exist for the EBS CSI pods to function).
- T004–T011 are CI gates that run after the apply. T004/T005/T006 are static/plan checks (independent of each other); T007–T011 are E2E SSM checks (independent of each other, all depend on the apply completing).
- Per P5/P6, T007–T011 are **user-managed verification** (SSM Run Command against the live cluster) — defined here but NOT added to `terraform-apply.yml`.
