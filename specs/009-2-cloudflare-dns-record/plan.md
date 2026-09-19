# Architecture Delta: Cloudflare DNS Record (replace Route 53)

**Branch**: `009-2-cloudflare-dns-record` | **Date**: 2026-09-17 | **Spec**: [specs/009-2-cloudflare-dns-record/spec.md]

## 1. Touch Points & File Impact Matrix

| File Path | Operation (Create/Modify/Delete) | Purpose / Exports |
| :--- | :--- | :--- |
| `terraform/modules/cluster-plumbing/main.tf` | Modify | Delete `aws_iam_role_policy.node_route53` (009) — dead after the switch |
| `terraform/environments/dev/main.tf` | Modify | Rename `null_resource.apply_route53_record` → `apply_cloudflare_record`; point the SSM command at the new script; update `--comment` (≤100 chars) + the two comment references to the old name |
| `terraform/environments/dev/scripts/create-route53-record.sh` | Delete | Replaced by `create-cloudflare-record.sh` |
| `terraform/environments/dev/scripts/create-cloudflare-record.sh` | Create | SSM script: token from SSM → ALB DNS poll → Cloudflare zone lookup → CNAME upsert (`proxied: false`) |

No manifest, variable, or module-output changes. The Ingress `tls` block and `demo-vijote-dev` Certificate (009) are untouched.

### 1.1 Exact Edits

**Edit A** — `terraform/modules/cluster-plumbing/main.tf`: delete the `aws_iam_role_policy.node_route53` resource (lines ~219–238, including its comment block). No other resource in the module references it.

**Edit B** — `terraform/environments/dev/main.tf`, `null_resource.apply_route53_record` (~line 744):
- Rename the resource to `apply_cloudflare_record`.
- Update the header comment block (009 → 009-2: Cloudflare is the DNS authority for `vijote.dev`; the Route 53 record was invisible).
- `triggers`: keep `domain` + `instance_id` (drop the `route53_ref` chain — the rename itself forces a fresh run).
- SSM command: `base64encode(file("${path.module}/scripts/create-cloudflare-record.sh"))` (was `create-route53-record.sh`).
- `--comment` → `"Create Cloudflare CNAME record for demo.vijote.dev (009-2)"` (56 chars — under the 100-char SSM cap).
- `depends_on` unchanged: `[null_resource.apply_aws_ccm, module.cluster_plumbing]`.
- Update the two comment references to the old name: line ~495 (cycle-avoidance note) and the module comment at line ~221 (deleted with Edit A).

**Edit C** — `scripts/create-cloudflare-record.sh` (new; full content in spec §1.2):
- Step (0): `aws ssm get-parameter --name /sdd-k8s-platform/secrets/cloudflare-api-token --with-decryption` (covered by the existing `node_ssm_parameters` policy — no IAM change).
- Step (1): ALB DNS poll from `ingress-nginx-controller` Service status (30×10s) — unchanged logic from 009.
- Step (2): `curl GET $CF_API/zones?name=vijote.dev&status=active` → zone ID (fail fast if absent).
- Step (3): GET existing CNAME → `PUT` (update) or `POST` (create) with `{"type":"CNAME","name":"demo.vijote.dev","content":"<ALB_DNS>","proxied":false}`.
- JSON parsing via `python3` (AL2023 default); `curl` defensively installed via `dnf`.

## 2. Architectural Boundaries & Dependency Flow

- **Infrastructure Layer (AWS & Terraform)**: `node_route53` IAM policy removed; the DNS record is now created via the Cloudflare REST API from the control plane.
- **Cluster Control Plane & Core Addons**: unchanged (kubeadm, Flannel, EBS CSI, CCM).
- **Platform Services**: unchanged (cert-manager, ingress-nginx).
- **Application Workloads**: unchanged (MySQL, app deployments, Ingress).
- **Dependency Flow (unchanged)**: `apply_aws_ccm` + `module.cluster_plumbing` → `apply_cloudflare_record`. The deliberate cycle-avoidance from 009 is preserved: `apply_app_frontend_ingress` does NOT depend on the DNS record resource (cert-manager retries HTTP-01 until DNS is live).
- **DNS authority**: `vijote.dev` stays authoritative at Cloudflare (user decision). The Route 53 `vijote.dev` hosted zone becomes unused (user may delete it manually to stop ~$0.50/month).

## 3. Provisioning & Rollout Stages

1. **Stage 1 - Terraform IaC**: `terraform apply` — `node_route53` deleted; `apply_route53_record` destroyed (no destroy provisioner → no-op); `apply_cloudflare_record` created and runs immediately (new resource). All other resources no-op.
2. **Stage 2 - SSM (in-place)**: the provisioner runs on the EXISTING control plane: SSM-agent wait → bootstrap-instance-id gate → `create-cloudflare-record.sh`. Step (0) reads the token from SSM (user prerequisite); step (1) reads the ALB DNS; step (2) finds the Cloudflare zone; step (3) upserts the CNAME.
3. **Stage 3 - Downstream (unchanged)**: once `demo.vijote.dev` resolves via Cloudflare, cert-manager's HTTP-01 challenge validates, the `demo-vijote-dev` Certificate issues, and HTTPS works. No re-apply needed — cert-manager retries automatically.

## 4. Verification Gates

- **IaC Validation**: `terraform fmt -check -recursive && terraform validate && terraform plan -detailed-exitcode` (plan shows ONLY the `node_route53` deletion + `apply_route53_record` destroy + `apply_cloudflare_record` create).
- **CNAME Record**: via SSM on the control plane — `curl -s -H "Authorization: Bearer $CF_TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&name=demo.vijote.dev"` → `content` = ALB DNS, `proxied` = `false`.
- **Certificate**: `kubectl get certificate demo-vijote-dev -n sdd-apps -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`.
- **Issuer**: `kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True`.
- **End-to-end**: `curl -sSf https://demo.vijote.dev/ -o /dev/null -w '%{http_code}\n'` → `200` and `curl -sSf https://demo.vijote.dev/api -o /dev/null -w '%{http_code}\n'` → `200` (proves DNS + TLS + routing together; no nslookup per AGENTS.md).
