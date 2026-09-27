# Current Session State

**Current Spec:**
`specs/015-14-ingress-apply-order` — COMPLETE and VERIFIED in cluster (commit `f7c1647`). All specs 015-10 → 015-14 implemented, pushed, and verified. White page saga RESOLVED.

**Objective:**
None active in this repo. Latest finding is a FRONTEND REPO code issue (not infra).

**Context (Why):**
Session arc: 015-10 (empty image tag = skip Deployment apply, no baseline nginx rollback) → 015-11/015-12 (single-ingress regex attempts, failed 3 ways: Prefix `/`, `/(.*)`, `/()(.*?)`) → 015-13 (split into `app-ingress-api` rewrite + `app-ingress` passthrough) → 015-14 (apply passthrough BEFORE api; ingress-nginx webhook host/path conflict resolved). Verified: assets serve correct Content-Type, unknown paths 404, `/api` routes to backend.

**Modified/Uncommitted Files:**
- `.coda/MEMORY.md` (gotchas: per-ingress rewrite annotations, apply order, LE rate-limit)
- `.coda/STATE.md` (this file)
- `.coda/docs/` (untracked; frontend agent handoff `handoff-ingress-frontend-rewrite.md`)

**Blockers/Unresolved Bugs:**
- Frontend repo bug: frontend calls `http://localhost:8080/api/shorten` instead of relative `/api/shorten` — browser-side call, localhost can never work. Fix in frontend repo: make API base URL relative (or `import.meta.env.VITE_API_URL ?? ""` with relative default). No infra changes needed.
- Cosmetic: LE cert rate-limited until 2026-09-27 01:39:59 UTC; cert-manager self-heals after (no action).

**Next Immediate Steps:**
- Frontend repo: fix API base URL to relative `/api/...`, push image, bump `frontend_image_tag` — 015-10 pipeline handles rollout.
- Key gotchas: rewrite annotations are PER-INGRESS (split API/frontend objects, 015-13); apply passthrough Ingress BEFORE rewrite Ingress (webhook conflict, 015-14); K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; placeholder occurrences exactly one per manifest (014).
