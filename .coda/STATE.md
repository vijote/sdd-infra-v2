# Current Session State

**Current Spec:**
`specs/015-11-ingress-frontend-path-capture` (implemented locally; NOT yet committed/pushed — awaiting user instruction)

**Objective:**
Fix the white page: ingress rewrite-target `/$2` applies to every path; frontend rule must be `/(.*)` so the rewrite is an identity for non-/api paths.

**Context (Why):**
Frontend agent handoff (`.coda/docs/handoff-ingress-frontend-rewrite.md`): `/assets/*` requests return `index.html` as `text/html` because the bare Prefix `/` rule has no capture groups, so `$2` is empty and everything is rewritten to `/`. Fix (015-11): frontend path `/(.*)` + `ImplementationSpecific`; bump `apply_app_services_ingress` manifest_rev trigger so SSM re-applies.

**Modified/Uncommitted Files:**
- `terraform/environments/dev/main.tf` (manifest_rev trigger bump)
- `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (frontend path /(.*) + comment fix)
- NEW: `specs/015-11-ingress-frontend-path-capture/` (spec, plan, tasks, checklist)
- `.coda/STATE.md` (this file)

**Blockers/Unresolved Bugs:**
- None known. `terraform fmt -check -recursive` + `terraform validate` pass.

**Next Immediate Steps:**
- Commit + push (user instruction), let CI apply, then validate: `curl -sI https://demo.vijote.dev/assets/index-DaMkeDWv.js | grep -i content-type` → `application/javascript`; `/api/healthz` still reaches backend.
- Key gotchas: K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; Job `spec.template` immutable (delete-before-apply, standalone); placeholder occurrences exactly one per manifest (014); ingress-level rewrite annotations apply to EVERY path (015-11).
