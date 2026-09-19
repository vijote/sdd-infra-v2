# Execution Graph (DAG): cert-manager K8s 1.28 Version Skew Fix

**Input**: Design documents from `/specs/004-13-cert-manager-k8s-version-skew/`
**Prerequisites**: `plan.md` (architecture), `spec.md` (requirements + AC)
**Estimate**: 1 implementation task + 4 verification gates

## Stage 1: Implementation

- [x] T001 [Stage 1: Platform] In `terraform/environments/dev/main.tf`, resource `null_resource.apply_cert_manager` (added by 004-1): (1) `triggers.cert_manager_ref` `"v1.21.1"` → `"v1.19.4"` (add `# 004-13: v1.20+ CRDs require K8s 1.30+ (selectableFields)` note), (2) SSM `--parameters` first command URL `https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml` → `.../v1.19.4/cert-manager.yaml`, (3) `--comment "Deploy cert-manager v1.21.1 + ClusterIssuers (004-1)"` → `--comment "Deploy cert-manager v1.19.4 + ClusterIssuers (004-1/004-13)"`. Do NOT touch: second SSM command (base64 issuers apply), SSM-agent wait loop, bootstrap-instance-id gate, poll loop, `depends_on`, `instance_id` trigger, or `manifests/cert-manager-issuers.yaml`

## Stage 2: Verification (CI / user-managed — per constitution P5/P6, agent does NOT run)

- [x] T002 [Stage 2: Verify] AC-001/AC-002 static: `terraform fmt -check -recursive` + `terraform validate` + `terraform plan -detailed-exitcode` — plan must show ONLY `null_resource.apply_cert_manager` replacement (trigger change); zero changes to other resources
- [x] T003 [Stage 2: Verify] AC-003: all 6 CRDs installed (via SSM: `kubectl get crd certificates.cert-manager.io challenges.cert-manager.io certificaterequests.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io orders.cert-manager.io -o name | wc -l` → `6`)
- [x] T004 [Stage 2: Verify] AC-004: controller + webhook + cainjector pods Ready (via SSM: `kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=300s` + `-webhook` + `-cainjector`)
- [x] T005 [Stage 2: Verify] AC-005/AC-006: both ClusterIssuers present (`kubectl get clusterissuer selfsigned letsencrypt-prod -o name | wc -l` → `2`) AND deployed image is v1.19.4 (`kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'` contains `v1.19.4`) (via SSM)
