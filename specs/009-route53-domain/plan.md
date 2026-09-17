# Architecture Delta: Route 53 Domain + Let's Encrypt TLS

**Branch**: `009-route53-domain` | **Date**: 2026-09-16 | **Spec**: specs/009-route53-domain/spec.md

## 1. Touch Points & File Impact Matrix

| File Path | Operation | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/environments/dev/variables.tf` | Modify | `ingress_host` default `"app.local"` → `"demo.vijote.dev"` |
| `terraform/environments/dev/main.tf` | Modify | (1) Add `null_resource.apply_route53_record` (after `apply_aws_ccm`, line ~732) — SSM: poll ALB DNS from ingress-nginx Service → look up `vijote.dev` zone ID → `UPSERT` A ALIAS record. (2) Extend `apply_app_frontend_ingress` `depends_on` (line 493) to `[null_resource.apply_app_backend, null_resource.apply_route53_record, null_resource.apply_cert_manager]` |
| `terraform/environments/dev/manifests/app-frontend-ingress.yaml` | Modify | Add `spec.tls` block to `app-ingress` (host `%%INGRESS_HOST%%`, `secretName: demo-vijote-dev-tls`) + new `Certificate` object `demo-vijote-dev` (`dnsNames: [%%INGRESS_HOST%%]`, `issuerRef: letsencrypt-prod`) |
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Add `aws_iam_role_policy.node_route53` (mirrors `node_aws_ccm`): `route53:ChangeResourceRecordSets`, `route53:ListResourceRecordSets`, `route53:GetHostedZone` on `*` (dev-only, 004-8 precedent) |

**4 files.** No new AWS resources in Terraform state (the Route 53 record is created via SSM, not a Terraform resource — the ALB is CCM-created, out of state). One new IAM policy on the existing node role.

## 2. Architectural Boundaries & Dependency Flow

- **Unchanged boundaries**: VPC, EC2, CNI, EBS CSI, MySQL, app workloads, CCM, cert-manager.
- **Changed components**:
  - **DNS**: `demo.vijote.dev` A ALIAS → CCM-created ALB (via SSM, post-CCM).
  - **TLS**: Ingress `tls` block + `Certificate` (cert-manager `letsencrypt-prod` HTTP-01).
  - **IAM**: node role gains Route 53 record-management actions (control plane uses the node profile, so SSM commands inherit it).
- **Dependency Flow**: `apply_app_frontend_ingress` (Ingress `tls` + `Certificate`) → `apply_aws_ccm` (ALB exists; pre-existing dep — CCM annotates the ingress Service) → **`apply_route53_record`** (domain live). `apply_cert_manager` (issuers) is a prerequisite for the Certificate. **The ingress does NOT depend on `apply_route53_record`** — that would be a cycle (route53_record → aws_ccm → ingress). The Certificate stays in "Issuing" until DNS is live; cert-manager retries HTTP-01 automatically, so it self-heals once the ALIAS record propagates.
- **HTTP-01 path**: Let's Encrypt → `http://demo.vijote.dev/.well-known/acme-challenge/...` → ALB (443/80 open, 004-7) → ingress-nginx → cert-manager solver.

## 3. Provisioning & Rollout Stages

1. **Stage 1 — Terraform IaC**: 4 file edits. `terraform fmt -check -recursive && terraform validate` must pass. Plan delta = 1 new `null_resource` + 1 new `aws_iam_role_policy` + `apply_app_frontend_ingress` re-apply (ingress_host change) + node-role policy attach. No AWS resource diffs beyond the IAM policy.
2. **Stage 2 — SSM Apply (control plane)**: On `terraform apply`:
   - `apply_route53_record` runs (after CCM): SSM-agent wait → bootstrap gate → poll `kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` (30×10s) → `aws route53 list-hosted-zones --query "HostedZones[?Name=='vijote.dev.'].Id"` (fail fast if empty) → `aws route53 change-resource-record-set` UPSERT A ALIAS `demo.vijote.dev.` → ALB DNS (`SetIdentifier demo-vijote-dev-alias`, `AliasTarget.HostedZoneId Z35SXDOTRQ7X7K`).
   - `apply_app_frontend_ingress` re-runs (ingress_host change + new `apply_cert_manager` dep): applies the Ingress with `tls` block + the `Certificate`. The Certificate enters "Issuing"; cert-manager retries HTTP-01 automatically until the ALIAS record (created later by `apply_route53_record`) propagates, then the cert is issued.
3. **Stage 3 — Verification (user-managed)**: AC-003–AC-006 via SSM/CLI (ALIAS record, cert READY, issuer READY, HTTPS 200). Not added to `terraform-apply.yml` per P5/P6.

## 4. Implementation Notes (binding)

- **`apply_route53_record` placement**: immediately after `apply_aws_ccm` (end of `main.tf`, line ~732) for dependency adjacency. Mirror the SSM block structure of `apply_cert_manager` (SSM-agent wait, bootstrap-instance-id gate, `--timeout-seconds 600`, poll loop).
- **Triggers**: `{ domain = var.ingress_host, instance_id = module.control_plane.control_plane_instance_id }` (004-10 recreation pattern).
- **ALB DNS poll**: the CCM may take a moment to populate the Service status; poll `kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` until non-empty (30×10s), fail if empty.
- **Zone lookup**: `aws route53 list-hosted-zones --query "HostedZones[?Name=='vijote.dev.'].Id" --output text` → strip the `hostedzone/` prefix. Fail fast with a clear message if empty (user prerequisite).
- **ALIAS record JSON**: `{"Comment":"sdd-k8s-platform demo.vijote.dev (009)","Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"demo.vijote.dev.","Type":"A","SetIdentifier":"demo-vijote-dev-alias","AliasTarget":{"HostedZoneId":"Z35SXDOTRQ7X7K","DNSName":"<ALB_DNS>"}}}]}`. `Z35SXDOTRQ7X7K` = us-east-1 ELB zone (AWS-documented).
- **Ingress manifest**: add `spec.tls` to the existing `app-ingress` Ingress (keep the `%%INGRESS_HOST%%` token — Terraform replaces it). Add the `Certificate` as a second object in the same file (multi-doc YAML, `---` separator). No `%%TOKEN%%` secrets in this manifest.
- **`apply_app_frontend_ingress` depends_on**: extend the existing `[null_resource.apply_app_backend]` to include ONLY `null_resource.apply_cert_manager`. **Do NOT add `apply_route53_record`** — it would create a cycle (`apply_route53_record` → `apply_aws_ccm` → `apply_app_frontend_ingress`, since the CCM already depends on the ingress to annotate its Service). The Certificate self-heals via cert-manager's automatic HTTP-01 retry once the ALIAS record is live.
- **Node IAM policy**: new `aws_iam_role_policy.node_route53` in `cluster-plumbing/main.tf`, mirroring `node_aws_ccm` (same `role = aws_iam_role.node.id` pattern).
- **Do NOT touch**: CCM resource, cert-manager resource, MySQL/backend resources, or the existing Ingress path rules.

## 5. Verification Gates

- **IaC (static, in `terraform-apply.yml`)**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (AC-001, AC-002 — plan delta = new null_resource + new IAM policy + ingress re-apply; no unexpected diffs).
- **Cluster/DNS (user-managed, via SSM/CLI, `KUBECONFIG=/etc/kubernetes/admin.conf`)**:
  - AC-003: `aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --query "ResourceRecordSets[?Name=='demo.vijote.dev.'].AliasTarget.DNSName" --output text` → ALB DNS
  - AC-004: `kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`
  - AC-005: `kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`
  - AC-006: `curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'` → `200` AND `curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'` → `200`
- **Testing Policy**: No unit/E2E/CI validation generation (P6). No nslookup (AGENTS.md) — DNS+TLS+routing proven by the HTTPS curl (AC-006). AC-003–AC-006 are user-managed, not added to workflows.
