# Current Session State

**Current Spec:**
`specs/015-14-ingress-apply-order` (implemented locally; NOT yet committed/pushed — awaiting user instruction)

**Objective:**
Fix the 015-13 apply failure: the ingress-nginx admission webhook rejected `app-ingress-api` because the stale pre-split `app-ingress` still claimed the /api path. Apply the passthrough `app-ingress` FIRST (replaces stale object, drops /api), then `app-ingress-api`.

**Context (Why):**
SSM stderr: "host demo.vijote.dev and path /api(/|$)(.*) is already defined in ingress sdd-apps/app-ingress". Fix (015-14): document order only — passthrough first, api second; manifest_rev trigger bump. Note: LE cert rate-limited until 2026-09-27 01:39:59 UTC (independent; cert-manager self-heals).

**Modified/Uncommitted Files:**
- `terraform/environments/dev/main.tf` (manifest_rev trigger bump)
- `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (document order: passthrough first, api second)
- NEW: `specs/015-14-ingress-apply-order/` (spec, plan, tasks, checklist)
- `.coda/STATE.md` (this file)

**Blockers/Unresolved Bugs:**
- None known. `terraform fmt -check -recursive` + `terraform validate` pass.

**Next Immediate Steps:**
- Commit + push (user instruction), let CI apply, then validate: `kubectl get ingress -n sdd-apps` shows both objects; `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`; fake path → 404; `/api/healthz` still reaches backend.
- Key gotchas: K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; Job `spec.template` immutable (delete-before-apply, standalone); placeholder occurrences exactly one per manifest (014); rewrite annotations are PER-INGRESS — split API (rewrite) and frontend (passthrough) Ingress objects (015-13); apply passthrough BEFORE api to avoid webhook host/path conflict (015-14).
