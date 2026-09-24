# Checklist: 012-3-backend-port-align

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Root cause identified (manifest port 80 vs Go app default 8080) | ✅ |
| CHK002 | Manifest contract declared (containerPort, probes, Service targetPort → 8080) | ✅ |
| CHK003 | Trigger bump contract defined (`manifest_rev = "012-3-port-8080"` on apply_app_backend) | ✅ |
| CHK004 | Acceptance criteria machine-verifiable (fmt/validate, grep counts, endpoints, rollout, curl) | ✅ |
| CHK005 | Security boundaries unchanged (no IAM/SG changes; intra-node 8080 already allowed) | ✅ |
| CHK006 | Frontend manifest explicitly out of scope (unchanged) | ✅ |
| CHK007 | Zero conversational narrative; technical content only | ✅ |
| CHK008 | No validation/test steps in workflow definitions (constitution §6) | ✅ |
| CHK009 | Spec under 200 lines | ✅ (56 lines) |
| CHK010 | Follow-on spec numbering per convention (012-3, not editing implemented 012/012-2) | ✅ |
