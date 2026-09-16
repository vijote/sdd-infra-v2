# Execution Graph (DAG): cert-manager + Let's Encrypt (TLS Automation)

**Input**: Design documents from `/specs/004-1-cert-manager/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 2 implementation tasks + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Platform] Create `terraform/environments/dev/manifests/cert-manager-issuers.yaml`: two `cert-manager.io/v1` ClusterIssuers — (1) `selfsigned` with `spec.selfSigned: {}`, (2) `letsencrypt-prod` with `spec.acme` (server `https://acme-v02.api.letsencrypt.org/directory`, email `admin@example.com`, `privateKeySecretRef.name: letsencrypt-prod-account-key`, solver `http01.ingress.class: nginx`). No secrets, no `%%TOKEN%%` placeholders, no `${VAR}` (safe for plain `base64encode(file(...))`, no `templatefile()`)
- [x] T002 [Stage 1: Platform] Add `null_resource.apply_cert_manager` to `terraform/environments/dev/main.tf` immediately after `apply_app_infrastructure` (line ~248): `depends_on = [null_resource.apply_app_infrastructure]`, `triggers = { cert_manager_ref = "v1.21.1", instance_id = module.control_plane.control_plane_instance_id }` (004-10 recreation pattern), local-exec (bash interpreter) mirroring `apply_app_infrastructure` — SSM command: (1) SSM-agent wait loop (30×10s) + `kubeadm-bootstrap-instance-id` gate (60×10s), (2) `aws ssm send-command` with `--timeout-seconds 600` + `--comment "Deploy cert-manager v1.21.1 + ClusterIssuers (004-1)"`, commands: `KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml` then `echo '<base64encode(file("${path.module}/manifests/cert-manager-issuers.yaml"))>' | base64 -d | KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -`, (3) poll `get-command-invocation` (60×10s) until `Success`, fail on `Failed`/`TimedOut`/`Cancelled` (Depends on T001)

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [ ] T003 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY 1 new null_resource (zero changes to existing resources)
- [ ] T004 [Stage 2: Verify] AC-003: cert-manager controller + webhook + cainjector pods Ready in `cert-manager` namespace (via SSM: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s` + `-webhook` + `-cainjector`)
- [ ] T005 [Stage 2: Verify] AC-004/AC-005: `kubectl get clusterissuer selfsigned -o jsonpath={.metadata.name}` → `selfsigned` AND `kubectl get clusterissuer letsencrypt-prod -o jsonpath={.metadata.name}` → `letsencrypt-prod` (via SSM)
- [ ] T006 [Stage 2: Verify] AC-006: `kubectl get crd certificates.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io -o name | wc -l` → `3` (via SSM)
