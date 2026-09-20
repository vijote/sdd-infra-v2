---
name: "speckit-specify"
description: "Create or update the technical feature specification with explicit infrastructure contracts and machine-verifiable acceptance criteria."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/specify.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before specification)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_specify` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
    After emitting the block above you MUST actually invoke the hook and wait for it to finish before continuing. Run it the same way you would run the command yourself in this agent/session (the invocation may differ from the literal `{command}` id shown above, e.g. a skills-mode agent runs it as `/skill:speckit-...` or `$speckit-...`). Emitting the block alone does not run the hook.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

The text the user typed after `/speckit-specify` in the triggering message **is** the feature description. Assume you always have it available in this conversation even if `$ARGUMENTS` appears literally below.

Given that feature description, do this:

1. **Generate a concise short name** (2-4 words) for the feature (e.g., `aws-k8s-cluster`, `cert-manager-ingress`, `mysql-ha-statefulset`).

2. **Create the spec feature directory**:
   - Resolve `SPECIFY_FEATURE_DIRECTORY` (e.g., `specs/001-aws-k8s-cluster`).
   - `mkdir -p SPECIFY_FEATURE_DIRECTORY`
   - Resolve active `spec-template` from `.specify/templates/spec-template.md`
   - Copy to `SPECIFY_FEATURE_DIRECTORY/spec.md`
   - Set `SPEC_FILE` to `SPECIFY_FEATURE_DIRECTORY/spec.md`
   - Persist to `.specify/feature.json`:
     ```json
     {
       "feature_directory": "<resolved feature dir>"
     }
     ```

3. **Load Context & Directives**:
   - Load `.specify/memory/constitution.md` for governing constraints (Zero Narrative Policy, Architecture First, Token Efficiency <200 lines, Machine-Verifiable Acceptance Gates).

4. **Execute Specification Flow**:
   - Extract technical entities, cloud resources, Kubernetes manifests, Helm charts, and storage/network requirements.
   - Define exact Terraform / HCL variable and resource contracts.
   - Define exact Kubernetes API versions, CRDs, and Helm values structures.
   - Define concrete storage & data migration contracts (StorageClasses, PVCs, MySQL init).
   - Construct machine-verifiable technical acceptance criteria (CLI commands: `terraform validate`, `helm lint`, `kubectl wait`, health checks).
   - Document explicit technical assumptions and constraints (CIDRs, IAM boundaries, instance types).
   - **Enforce <200 lines total length** for token efficiency.

5. **Specification Quality Validation**:
   - Create quality checklist at `SPECIFY_FEATURE_DIRECTORY/checklists/requirements.md` using the technical checklist structure:
     - Technical contracts declared (Terraform HCL, Kubernetes YAML, Helm values)
     - Machine-verifiable acceptance criteria (executable CLI commands)
     - Security, IAM, and network boundaries specified
     - Zero conversational narrative or marketing fluff
   - Review and update checklist status.

## Mandatory Post-Execution Hooks

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, execute hooks under `hooks.after_specify` as defined in the standard SpecKit protocol.

## Completion Report

Report completion to the user with:
- `SPECIFY_FEATURE_DIRECTORY` — the feature directory path
- `SPEC_FILE` — the spec file path
- Technical acceptance criteria summary
- Readiness for `/speckit-plan` or `/speckit-clarify`
