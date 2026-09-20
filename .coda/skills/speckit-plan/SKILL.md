---
name: "speckit-plan"
description: "Execute the implementation planning workflow to generate a concise Architecture Delta and File Impact Matrix."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/plan.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the appropriate hook block based on its `optional` flag.

## Outline

1. **Setup**: Run `.specify/scripts/powershell/setup-plan.ps1 -Json` from repo root and parse JSON for `FEATURE_SPEC`, `IMPL_PLAN`, `SPECS_DIR`, `BRANCH`.

2. **Load context**: Read `FEATURE_SPEC` (`spec.md`) and `.specify/memory/constitution.md`. Load `IMPL_PLAN` template from `.specify/templates/plan-template.md`.

3. **Execute Architecture Delta Workflow**:
   - Construct the **Touch Points & File Impact Matrix**: Explicit table mapping every file path to its Operation (`Create`, `Modify`, `Delete`) and its specific Purpose/Exports (Terraform modules, Kubernetes manifests, Helm values, shell bootstrap scripts).
   - Define **Architectural Boundaries & Dependency Flow**: Map AWS infrastructure components, cluster bootstrap layers, platform addons (cert-manager), and stateful workloads (MySQL).
   - Formulate **Provisioning & Rollout Stages**: Break the rollout into clear sequential phases (Terraform IaC → Kubeadm Bootstrap → Core Addons → Platform Services → Workloads).
   - Keep the generated `plan.md` strictly under 200 lines for token efficiency.

## Mandatory Post-Execution Hooks

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, execute hooks under `hooks.after_plan` as defined in the standard SpecKit protocol.

## Completion Report

Report branch, `IMPL_PLAN` path, and summary of the File Impact Matrix and Rollout Stages.