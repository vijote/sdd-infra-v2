---
name: "speckit-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md using the session isolation protocol."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before implementation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_implement` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the appropriate hook block based on its `optional` flag.

## Outline

1. Run `.specify/scripts/powershell/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks` from repo root and parse `FEATURE_DIR` and `AVAILABLE_DOCS` list.

2. **Check Quality Gates**:
   - Verify `FEATURE_DIR/checklists/requirements.md` (or custom technical checklists) if present.
   - If unchecked blocking items exist, prompt the user before proceeding.

3. **Session Isolation Execution Loop**:
   For each task in `FEATURE_DIR/tasks.md` in dependency order:
   - **Isolate Payload Context**:
     - Load `.specify/memory/constitution.md`
     - Extract the active task description, target file path, and relevant contract snippet from `spec.md`/`plan.md`
   - **Execute 1:1 Implementation**:
     - Create or edit the exact target file (Terraform `.tf`, Kubernetes `.yaml`, Helm values, shell script)
     - Maintain strict formatting and schema compliance
   - **Update Progress**:
     - Mark completed task as `[x]` in `tasks.md`
     - Halt immediately on non-parallel failure; report actionable error output

4. **Completion Confirmation**:
   - Confirm all tasks in `tasks.md` are checked `[x]`.
   - All validation and testing is handled personally by the user per constitution Section 6.

## Mandatory Post-Execution Hooks

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, execute hooks under `hooks.after_implement` as defined in the standard SpecKit protocol.

## Completion Report

Report final execution status with summary of created/modified Terraform modules, Kubernetes manifests, and Helm configurations. All validation and testing is handled personally by the user.