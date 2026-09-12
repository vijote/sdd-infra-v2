# Architecture Delta: MySQL StatefulSet (In-Cluster Database)

**Branch**: `005-mysql-statefulset` | **Date**: 2026-09-12 | **Status**: Draft

## 1. File Impact Matrix

| File | Op | Purpose / Exports |
|------|----|-------------------|
| `terraform/environments/dev/main.tf` | Modify | Add 2 `data "aws_ssm_parameter"` datasources (`/sdd-k8s-platform/secrets/mysql-root-password`, `/sdd-k8s-platform/secrets/mysql-password`) + `null_resource.apply_mysql` (SSM-agent wait → 003-11 bootstrap gate → send-command: base64-decode manifest → `kubectl apply -f -`). `depends_on = [null_resource.apply_app_infrastructure]`. |
| `terraform/environments/dev/manifests/mysql.yaml` | Create | 3 objects in `sdd-apps`: Secret `mysql-secret` (with `%%TOKEN%%` placeholders), StatefulSet `mysql` (mysql:8.0.36, 1 replica, PVC on `ebs-gp3`), Service `mysql` (ClusterIP:3306). |

No new AWS resources. No new module. No CloudFormation change (PowerUserAccess already grants `ssm:GetParameter`). No GitHub secret/vars.

## 2. Architecture Delta

### 2.1 Secrets flow (new reference pattern)
```
SSM Parameter Store (SecureString, manual one-time)
  └─ data "aws_ssm_parameter" (Terraform, read-only)
       └─ replace(file("mysql.yaml"), "%%TOKEN%%", base64encode(param.value))
            └─ base64encode(whole manifest) → SSM command: echo <b64> | base64 -d | kubectl apply -f -
                 └─ K8s Secret data: field (base64 by definition)
```
- Passwords never appear in the SSM command line (only as base64 inside the base64'd manifest).
- `%%TOKEN%%` placeholders: `%%MYSQL_ROOT_PASSWORD_B64%%`, `%%MYSQL_PASSWORD_B64%%` (user/db are non-secret constants, written directly in the manifest).
- Sidesteps the 003-6 JSON-escaping gotcha and YAML special-char issues entirely.

### 2.2 StatefulSet design
- Image `mysql:8.0.36` (pinned), 1 replica, `volumeClaimTemplates` → `mysql-data` on `ebs-gp3` (10Gi, RWO).
- Env from `mysql-secret` (MYSQL_ROOT_PASSWORD, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE).
- Readiness probe: `mysqladmin ping -h 127.0.0.1 -uroot -p"$MYSQL_ROOT_PASSWORD"` (auth-aware — only ready when accepting connections).
- Liveness probe: `mysqladmin ping -h 127.0.0.1` (unauthenticated — process-alive check).
- Resources: requests 256Mi, limits 512Mi.

### 2.3 Provisioning order
`apply_mysql` depends on `apply_app_infrastructure` (needs `sdd-apps` ns + `ebs-gp3` SC + EBS CSI driver). The 003-11 bootstrap gate (instance-id signal) is reused verbatim.

## 3. Provisioning & Rollout Stages

1. **Manual (one-time, before first apply)**: create the 2 SecureString parameters (documented in spec §1.1).
2. **Terraform apply** — datasources read the params; `apply_mysql` trigger fires (first run) → SSM command applies the manifest.
3. **PVC provisioning** — EBS CSI driver creates the gp3 volume (first real exercise of the 004 storage stack).
4. **Pod readiness** — MySQL container starts, initializes the data directory, passes the readiness probe.

## 4. Verification Gates (CI / user-managed, per P5/P6)

- **AC-001/AC-002** (static, existing `terraform-apply.yml`): `terraform fmt -check -recursive && terraform validate`; `terraform plan -detailed-exitcode`.
- **AC-003** (SSM): `kubectl get secret mysql-secret -n sdd-apps` — all 4 keys present.
- **AC-004** (SSM): `kubectl get pvc mysql-data-mysql-0 -n sdd-apps` — phase `Bound`.
- **AC-005** (SSM): `kubectl rollout status statefulset/mysql -n sdd-apps --timeout=600s`.
- **AC-006** (SSM): `kubectl exec -n sdd-apps mysql-0 -- sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1"'` (password from pod env, never in the command).

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| SecureString params missing → datasources fail at plan time | Documented manual prerequisite; fail-fast with a clear "parameter not found" error. |
| PVC stuck `Pending` (EBS CSI issue) | 004-3 verified the driver running; AC-004 polls up to 10 min and surfaces the failure. |
| Readiness probe too strict (slow first init) | `rollout status --timeout=600s` gives MySQL 10 min for first-time data-dir init. |
| `%%TOKEN%%` replacement misses a placeholder | Only 2 tokens; `replace()` is exact-literal; a missed token would show as a literal `%%...%%` in the Secret and AC-006 would fail auth. |
| Re-apply after password rotation | Re-run the provisioner (trigger change or `terraform taint`) — `kubectl apply` updates the Secret; MySQL picks up new creds on restart. |
