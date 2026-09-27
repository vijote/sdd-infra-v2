# Current Session State

**Current Spec:**
`specs/015-10-empty-tag-skip-apply` (implemented locally; NOT yet committed/pushed — awaiting user instruction)

**Objective:**
Empty image tag must SKIP the app's Deployment apply instead of rolling it back to baseline nginx:alpine.

**Context (Why):**
Backend repo dispatches `deploy-images.yml` with only `backend_image_tag`; `frontend_image_tag` defaults to `""`, and Terraform's old semantics treated empty as "use baseline nginx:alpine" — rolling the user's deployed frontend back to stock nginx on every backend deploy. Fix (015-10): count-gate both Deployment null_resources on non-empty tag; split Deployment manifests from Service/Ingress manifests; NEW always-applied `apply_app_services_ingress` applies backend Service + frontend Service/Ingress/Certificate on every apply (fresh-cluster completeness).

**Modified/Uncommitted Files:**
- `terraform/environments/dev/main.tf` (count-gating, locals cleanup, new services/ingress resource, depends_on rewiring)
- `terraform/environments/dev/variables.tf` (descriptions)
- `terraform/environments/dev/manifests/app-backend.yaml` (Deployment only)
- `terraform/environments/dev/manifests/app-frontend-ingress.yaml` (Service+Ingress only)
- NEW: `manifests/app-backend-service.yaml`, `manifests/app-frontend.yaml`
- NEW: `specs/015-10-empty-tag-skip-apply/` (spec, plan, tasks, checklist)
- `.coda/MEMORY.md`, `.coda/STATE.md`, `specs/015-6-.../tasks.md` (from earlier)

**Blockers/Unresolved Bugs:**
- None known. `terraform fmt -check -recursive` + `terraform validate` pass.

**Next Immediate Steps:**
- Commit + push (user instruction), let CI apply, then validate: backend-only dispatch must NOT change `app-frontend` image; `kubectl get ingress app-ingress -n sdd-apps` still present after any apply.
- Key gotchas: K8s Job `command` REPLACES ENTRYPOINT (use `args`); always set `imagePullSecrets: ecr-pull-secret` on private-image workloads; Job `spec.template` immutable (delete-before-apply, standalone); placeholder occurrences exactly one per manifest (014).
