---
name: read-project
description: >-
  Read the frontmatter of every spec under specs/ to get a one-glance, whole-picture map of the project — what each spec is, its status, and its date — without reading the full spec bodies.
---

# Read-Project Skill

This skill produces a compact, whole-project overview by reading **only the frontmatter** of each spec. It is the fast way to see every spec at a glance (name, one-sentence overview, status, date) without consuming tokens on full spec bodies.

## Spec Layout

Specs live in numbered folders under `specs/` (e.g. `specs/003-golangci-lint-pin/`), each containing a single `spec-plan-tasks.md`. Every spec file begins with a YAML frontmatter block:

```yaml
---
name: 003-golangci-lint-pin
description: Pin golangci-lint to v2.13.2 and setup-go to 1.27.1 in CI to fix the Go version mismatch lint failure.
date: 2026-09-22
status: Approved
---
```

The frontmatter is the trace: `name` (spec id), `description` (one-sentence overview), `date`, `status`.

## Steps

1. **Discover specs**: Use glob with pattern `specs/*/spec-plan-tasks.md` to list every spec file.
2. **Extract frontmatter only**: For each file, read just the leading frontmatter block (the lines between the first `---` and the closing `---`, typically the first ~6 lines). Do **not** read the full spec body.
   - Efficient alternative: run a single grep for the four fields across all spec files, e.g. pattern `^(name|description|date|status):` with `include: spec-plan-tasks.md` and `path: specs`, then group the matches by file.
3. **Build the overview**: Present a single dotted (bulleted) list, one bullet per spec, ordered by `name` (numeric prefix). Each bullet is a one-line "understanding point" — the spec id, its status, and its one-sentence overview:

   - `001-go-backend-scaffold` — **Approved** (2026-09-20): Scaffold a Go backend with chi HTTP server, envconfig config, /healthz endpoint, and automated CI.
   - `002-dockerfile` — **Approved** (2026-09-21): Multi-stage Dockerfile (golang:1.27-alpine → distroless) + .dockerignore to containerize the Go backend.
   - `003-golangci-lint-pin` — **Approved** (2026-09-22): Pin golangci-lint to v2.13.2 and setup-go to 1.27.1 in CI to fix the Go version mismatch lint failure.

4. **Flag the active spec**: Read `.coda/feature.json` (`feature_directory` field) and append `← active` to the matching bullet so the reader sees where work is focused.
5. **Report gaps**: If any spec file is missing frontmatter or a field is absent, add a bullet for it explicitly (e.g. `- `004-foo` — ⚠️ missing frontmatter`) rather than guessing.

## Output Rules

- Keep the output to the dotted list plus at most a one-line note. No narrative, no per-spec elaboration.
- Do **not** read full spec bodies, `STATE.md`, or the repository beyond the frontmatter and `feature.json`.
- If `specs/` is empty or no `spec-plan-tasks.md` files exist, say so in one line.
