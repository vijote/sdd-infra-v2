---
name: sum-up
description: >-
  Use this skill at the end of a session to summarize the current work and hand off the state for the next session. This updates the project state so the agent can resume easily later.
---

# Sum-Up Skill

This skill allows you to summarize the current session's progress and update the `.coda/STATE.md` file. This creates a compact entry point for the next session, preventing the need to re-read all project specs.

## Steps

1. **Analyze Current State:**
   - Review the current conversation to identify the spec being worked on, the objective, and the context (why it's being done).
   - Identify any blockers, unresolved bugs, and the next immediate steps.
   - Run `git status` to get a list of recently modified or uncommitted files.

2. **Generate Summary:**
   - Synthesize this information into a concise summary using the exact format provided below.

3. **Update State File:**
   - Overwrite the file at `.coda/STATE.md` with your generated summary. Do not ask for user confirmation before writing, just overwrite it directly.

## Format for `.coda/STATE.md`

Use the following Markdown format for the state file:

```markdown
# Current Session State

**Current Spec:** 
[Name or link to the spec currently being developed]

**Objective:**
[Super short description of the objective of the current work]

**Context (Why):**
[Explain why this is being done (e.g., bug fix, feature addition)]

**Modified/Uncommitted Files:**
- [file 1]
- [file 2]

**Blockers/Unresolved Bugs:**
- [List any blockers or bugs, or write "None"]

**Next Immediate Steps:**
- [Step 1]
- [Step 2]
```
