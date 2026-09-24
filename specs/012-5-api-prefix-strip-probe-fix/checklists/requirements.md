# Checklist: 012-5-api-prefix-strip-probe-fix

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Root cause identified (probes hardcoded `/`; ingress passes `/api` unstripped) | ✅ |
| CHK002 | Ingress rewrite contract declared (use-regex + rewrite-target + regex path) | ✅ |
| CHK003 | Conditional probe path contract declared (`%%BACKEND_PROBE_PATH%%` + local) | ✅ |
| CHK004 | Trigger bump contract defined (`manifest_rev = "012-5-probe-path"`) | ✅ |
| CHK005 | Acceptance criteria machine-verifiable (fmt/validate, grep counts, terraform console, rollout, curl, ingress annotations) | ✅ |
| CHK006 | Both modes covered: baseline (/, 80) and tagged (/healthz, 8080) | ✅ |
| CHK007 | Frontend rule safety justified (/ does not match /api regex) | ✅ |
| CHK008 | Security boundaries unchanged (no IAM/SG changes) | ✅ |
| CHK009 | Zero conversational narrative; technical content only | ✅ |
| CHK010 | Spec under 200 lines | ✅ (71 lines) |
