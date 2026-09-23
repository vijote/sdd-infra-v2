# Checklist: 012-2-ecr-pull-secret-server-fix

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Root cause identified (full repo URL as `--docker-server`; kubelet needs bare registry host) | ✅ |
| CHK002 | Script fix contract declared (`REGISTRY="${REGISTRY%%/*}"` host-only strip) | ✅ |
| CHK003 | `script_rev` trigger bump contract defined (`014-guard-fix` → `012-2-server-fix`) | ✅ |
| CHK004 | Acceptance criteria machine-verifiable (fmt/validate, grep count, kubectl jsonpath, rollout status, plan) | ✅ |
| CHK005 | Security boundaries unchanged (no IAM/SG/API exposure changes) | ✅ |
| CHK006 | Placeholder single-occurrence rule respected (014 gotcha) | ✅ |
| CHK007 | Zero conversational narrative; technical content only | ✅ |
| CHK008 | No validation/test steps in workflow definitions (constitution §6) | ✅ |
| CHK009 | Spec under 200 lines | ✅ (55 lines) |
| CHK010 | Follow-on spec numbering per convention (012-2, not editing implemented 011/012) | ✅ |
