---
name: recap
description: >-
  Use this skill at the beginning of a new session or when you need to quickly get up to speed on what was being worked on previously. This will help you resume work without having to read through all the specifications in the project.
---

# Recap Skill

This skill allows you to quickly understand the current state of this project without consuming a large number of tokens reading through all specifications.

## Project Context

This is a spec-driven development repository using the SpecKit methodology. Work is organized as numbered spec folders under `specs/` (e.g., `specs/004-16-letsencrypt-contact-email`), each containing `spec.md`, `plan.md`, `tasks.md`, and optionally `checklists/` and `validate.sh`. The active spec is tracked in `.specify/feature.json`. The development cycle is: specify → plan → tasks → implement.

## Steps

1. Read the `.specify/feature.json` file in the root of the project. It contains the `feature_directory` field, which points to the spec folder currently being developed (e.g., `specs/004-16-letsencrypt-contact-email`).
2. Read the `.coda/STATE.md` file in the root of the project. Understand the information provided in the file, which includes:
   - The current spec being developed.
   - Its super short objective.
   - The reason why we are doing this (e.g., fixing a specific bug, implementing a feature).
   - Blockers, uncommitted files, and next immediate steps.
3. Cross-check: if `.coda/STATE.md` is missing or its "Current Spec" disagrees with `feature.json`, trust `feature.json` as the source of truth for which spec is active.
4. Use this context as your entry point for the session.
5. **Do not** attempt to read all specs or the entire repository to figure out where we left off. Rely on the context provided in `.specify/feature.json` and `.coda/STATE.md`, and only read the specific spec or files mentioned there.
