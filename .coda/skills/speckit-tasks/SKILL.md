---
name: "speckit-tasks"
description: "Generate an actionable, dependency-ordered micro-DAG tasks.md for the feature based on technical contracts and architecture delta."
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/tasks.md"
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before tasks generation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_tasks` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the appropriate hook block based on its `optional` flag.

## Outline

1. **Setup**: Run `.specify/scripts/powershell/setup-tasks.ps1 -Json` from repo root and parse `FEATURE_DIR`, `TASKS_TEMPLATE_CONTENT`, `TASKS_TEMPLATE`, and `AVAILABLE_DOCS` list.

2. **Load design documents**: Read from `FEATURE_DIR`:
   - **Required**: `plan.md` (File Impact Matrix & Rollout Stages), `spec.md` (Contracts & Acceptance Criteria)
   - **Governance**: `.specify/memory/constitution.md` (DAG Principle, 1:1 file edit tasks)

3. **Execute Task Generation Workflow**:
   - Extract every file touch point from the `plan.md` File Impact Matrix.
   - Extract all technical acceptance criteria from `spec.md`.
   - Organize tasks into architectural stages:
     - **Stage 1**: Infrastructure & Terraform Foundations (VPC, IAM, Security Groups, EC2 nodes)
     - **Stage 2**: Cluster Bootstrap & Core Addons (kubeadm init/join, CNI, CSI/StorageClass)
     - **Stage 3**: Platform Services & Ingress (cert-manager, ClusterIssuer, Ingress Controller)
     - **Stage 4**: Data Layer & Workloads (MySQL StatefulSet/Helm, PVC, Secrets, Init scripts)
     - **Stage 5**: Verification, Health Probes & Acceptance Validation (Linting, dry-runs, connectivity checks)
   - Construct explicit dependency chains using `(Depends on Txxx)`.

4. **Task Format (STRICT)**:
   Every task MUST strictly adhere to this format:
   ```text
   - [ ] T001 [Stage N: Name] Action description in path/to/file (Depends on Txxx)
   ```
   - **Checkbox**: `- [ ]`
   - **Task ID**: Sequential zero-padded number (`T001`, `T002`, `T003`...)
   - **Stage**: Stage indicator (`[Stage 1: Terraform]`, `[Stage 2: Bootstrap]`, etc.)
   - **Description & Path**: Exact 1:1 file path and concrete action
   - **Dependency**: Explicit preceding task IDs `(Depends on T001, T002)` or omitted for root tasks

5. **Write `tasks.md`**: Persist to `FEATURE_DIR/tasks.md`.

## Mandatory Post-Execution Hooks

Check if `.specify/extensions.yml` exists in the project root.
- If it exists, execute hooks under `hooks.after_tasks` as defined in the standard SpecKit protocol.

## Completion Report

Output path to generated `tasks.md` with:
- Total task count
- Stage breakdown
- Parallelization opportunities
- Verification task mappings
