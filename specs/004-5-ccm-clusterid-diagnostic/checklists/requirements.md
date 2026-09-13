# Technical Quality Checklist: CCM ClusterID Diagnostic

**Purpose**: Validate technical rigor, infrastructure contracts, and machine-verifiability before planning/execution.
**Created**: 2026-09-13
**Feature**: `004-5-ccm-clusterid-diagnostic`

## Infrastructure Contracts
- [x] CHK001: Two-file change — `manifests/aws-ccm.yaml` (args) + `dev/main.tf` (`apply_aws_ccm` command + trigger); no new resource, no IAM, no module
- [x] CHK002: `--v=4` appended to existing CCM args (glog verbosity; standard CCM diagnostic for AWS call tracing)
- [x] CHK003: CCM version unchanged (`v1.28.11-eks-1-28-64`)
- [x] CHK004: `rollout status` replaced by `rollout restart` + `sleep 30` + log capture (rollout status can never succeed while the CCM crash-loops — it would fail the provisioner)
- [x] CHK005: Log capture uses `--previous` with `||` fallback (no `--all-containers` — incompatible with `--previous`; fallback covers a pod that hasn't crashed yet)
- [x] CHK006: `depends_on`, SSM-agent wait, bootstrap-instance-id gate, poll loop, `--timeout-seconds 600`, Service annotation step all unchanged

## Re-run / Idempotency
- [x] CHK007: New trigger `ccm_log_level = "4"` forces the provisioner re-run (003-6 mechanism)
- [x] CHK008: `rollout restart` + `kubectl apply` idempotent — safe to re-run on steady state
- [x] CHK009: SSM command remains a single `&&`-chained string (AWS-RunShellScript short-circuit gotcha); `(a || b)` is valid bash inside the JSON string

## Diagnostic Coverage
- [x] CHK010: `--v=4` logs every AWS API call (DescribeInstances/DescribeSubnets/DescribeVpcs) + any AccessDenied — sufficient to identify the failing call
- [x] CHK011: All external factors already ruled out (tag on VPC, worker in cluster VPC, IMDS ID, manual DescribeInstances→Vpcs chain from the worker, node profile) — the trace isolates the CCM's internal call path
- [x] CHK012: Evidence lands in the SSM invocation output (AC-004) — no extra retrieval step needed

## Acceptance Criteria
- [x] CHK013: All 5 ACs machine-verifiable (terraform fmt/validate/plan + grep + SSM output inspection)
- [x] CHK014: AC-002 pins the plan delta to exactly 1 `null_resource` re-run
- [x] CHK015: AC-003 greps the manifest for `--v=4`
- [x] CHK016: AC-004/AC-005 define the evidence contract (trace present → root cause identified → drives 004-6)

## Scope Discipline
- [x] CHK017: No root-cause fix in this spec (that is 004-6, scoped from the AC-004/AC-005 evidence)
- [x] CHK018: No IAM changes, no CCM version change, no ELB/Ingress ADDRESS verification (blocked until the CCM is fixed)
