# Current Session State

**Current Spec:**
`specs/015-12-frontend-path-second-capture-group` (implemented locally; NOT yet committed/pushed — awaiting user instruction)

**Objective:**
Fix the persistent rewrite-to-`/`: rewrite-target `/$2` requires a SECOND capture group; `/(.*)` (015-11) has only one, so `$2` was undefined and everything still rewrote to `/`.

**Context (Why):**
Verified live: `/assets/*` AND fake paths return `index.html` as `text/html`. Fix (015-12): frontend path `/()(.*?)` ($1 = "", $2 = rest of URL → identity rewrite); bump `apply_app_services_ingress` manifest_rev trigger so SSM re-applies. Note: LE cert rate-limited until 2026-09-27 01:39:59 UTC (independent; cert-manager self-heals).

**Modified/Uncommitted Files:**
- `terraform/environments/dev/main.tf` (manifest_rev trigger bump)
- `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (frontend path /()(.*?) + comment fix)
- NEW: `specs/015-12-frontend-path-second-capture-group/` (spec, plan, tasks, checklist)
- `.coda/STATE.md` (this file)

**Blockers/Unresolved Bugs:**
- None known. `terraform fmt -check -recursive` + `terraform validate` pass.

**Next Immediate Steps:**
- Commit + push (user instruction), let CI apply, then validate: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`; fake path → 404; `/api/healthz` still reaches backend.
- Key gotchas: K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; Job `spec.template` immutable (delete-before-apply, standalone); placeholder occurrences exactly one per manifest (014); ingress-level rewrite annotations apply to EVERY path and $2 needs a SECOND capture group — frontend rule `/()(.*?)` (015-12).
