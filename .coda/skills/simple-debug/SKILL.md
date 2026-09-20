---
name: simple-debug
description: >-
  Use this skill when presented with a vague error (e.g., 'Cluster apply exited with status Failed') to prevent overthinking and long iterative debugging loops.
---

# Simple Debug Skill

This skill enforces a strict, simplified approach to debugging vague errors. Its purpose is to prevent you from falling into long, iterative thinking loops where you guess multiple causes and evaluate them all internally.

## Directive

When this skill is invoked or when you are debugging a vague error:

1. **Stop Internal Debate**: Do not re-evaluate or list multiple possible causes in your thoughts.
2. **Formulate ONE Hypothesis**: Formulate exactly **one** strong hypothesis for what is causing the error. Base this hypothesis on:
   - The most recent file changes.
   - The current context found in `.agents/STATE.md`.
   - Your general knowledge of the project.
3. **Wait for Confirmation**: State your single hypothesis to the user and **stop**. Ask the user to confirm if the hypothesis is correct or to provide the full error logs before you take any further action.

Do not attempt to fix the issue or explore other possibilities until the user responds to your single hypothesis.
