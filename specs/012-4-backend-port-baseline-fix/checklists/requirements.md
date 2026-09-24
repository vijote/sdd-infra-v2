# Checklist: 012-4-backend-port-baseline-fix

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Root cause identified (012-3 hardcoded 8080 breaks nginx baseline bootstrap) | ✅ |
| CHK002 | Conditional port contract declared (local + `%%BACKEND_PORT%%` substitution) | ✅ |
| CHK003 | Multi-occurrence placeholder justified (014 gotcha applies to guards only; none here) | ✅ |
| CHK004 | Trigger bump contract defined (`manifest_rev = "012-4-port-baseline"`) | ✅ |
| CHK005 | Acceptance criteria machine-verifiable (fmt/validate, grep counts, terraform console, rollout, endpoints, curl) | ✅ |
| CHK006 | Both modes covered: baseline (empty tag → 80) and tagged (→ 8080) | ✅ |
| CHK007 | Security boundaries unchanged (no IAM/SG changes) | ✅ |
| CHK008 | Dispatch contract unchanged (backend repo sends tag only) | ✅ |
| CHK009 | Zero conversational narrative; technical content only | ✅ |
| CHK010 | Spec under 200 lines | ✅ (61 lines) |
