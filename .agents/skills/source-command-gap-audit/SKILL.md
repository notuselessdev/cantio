---
name: "source-command-gap-audit"
description: "Spawn regression-auditor. Produces test-gap report under docs/."
---

# source-command-gap-audit

Use this skill when the user asks to run the migrated source command `gap-audit`.

## Command Template

Spawn the `regression-auditor` subagent. Brief: "Run the full audit per your definition. Write report to `docs/test-gaps-<YYYY-Q[1-4]>.md`. Update `docs/.last-audit-date`."

When done, print:
- Report path.
- Total gap count.
- Top 3 priorities for `test-author` to address next.
