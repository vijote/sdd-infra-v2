# Checklist: 012-6-ingress-annotations-placement

| CHK# | Requirement | Status |
|------|-------------|--------|
| CHK001 | Root cause identified (annotations under `spec:` instead of `metadata:`; K8s 1.28 strict decoding rejects `spec.annotations`) | ✅ |
| CHK002 | Manifest fix contract declared (move annotations block to `metadata`, remove from `spec`) | ✅ |
| CHK003 | Trigger bump contract declared (`manifest_rev` → `012-6-annotation-placement` on `apply_app_frontend_ingress`) | ✅ |
| CHK004 | Acceptance criteria machine-verifiable (fmt, plan, CI, kubectl jsonpath, curl) | ✅ |
| CHK005 | No new AWS resources / modules / variables | ✅ |
| CHK006 | Single `%%INGRESS_HOST%%` occurrence preserved (014 gotcha) | ✅ |
| CHK007 | Zero narrative policy respected | ✅ |
| CHK008 | Spec under 200 lines | ✅ |
| CHK009 | No validation steps inside workflow definitions (constitution §6) | ✅ |
| CHK010 | Sequential numbering convention followed (012-6 follow-on of 012-5) | ✅ |
