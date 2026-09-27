# Current Session State

**Current Spec:**
`specs/015-13-split-ingress-objects` (implemented locally; NOT yet committed/pushed — awaiting user instruction)

**Objective:**
Fix the persistent rewrite-to-`/` for good: rewrite annotations are PER-INGRESS, so split into two Ingress objects — API (rewrite) and frontend (passthrough).

**Context (Why):**
Verified live: `/()(.*?)` (015-12) still rewrote everything to `/` because `(.*?)` is non-greedy (matches empty). Three single-ingress regex attempts failed (Prefix /, /(.*) , /()(.*?)). Fix (015-13): `app-ingress-api` (use-regex + rewrite-target /$2, `/api(/|$)(.*)` -> backend) + `app-ingress` (NO rewrite annotations, `/` Prefix -> frontend); nginx regex locations beat prefix so /api wins. Note: LE cert rate-limited until 2026-09-27 01:39:59 UTC (independent; cert-manager self-heals).

**Modified/Uncommitted Files:**
- `terraform/environments/dev/main.tf` (manifest_rev trigger bump)
- `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Ingress split: app-ingress-api + app-ingress passthrough)
- NEW: `specs/015-13-split-ingress-objects/` (spec, plan, tasks, checklist)
- `.coda/STATE.md` (this file)

**Blockers/Unresolved Bugs:**
- None known. `terraform fmt -check -recursive` + `terraform validate` pass.

**Next Immediate Steps:**
- Commit + push (user instruction), let CI apply, then validate: `curl -skI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`; fake path → 404; `/api/healthz` still reaches backend.
- Key gotchas: K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; Job `spec.template` immutable (delete-before-apply, standalone); placeholder occurrences exactly one per manifest (014); rewrite annotations are PER-INGRESS — split API (rewrite) and frontend (passthrough) Ingress objects (015-13).
