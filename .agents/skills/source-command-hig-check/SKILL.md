---
name: "source-command-hig-check"
description: "Spawn hig-reviewer + a11y-auditor in parallel on the current diff."
---

# source-command-hig-check

Use this skill when the user asks to run the migrated source command `hig-check`.

## Command Template

Spawn both agents in parallel using the Agent tool. Brief both with: "Review the
current uncommitted diff. Output format per your definition. Be terse."

After both finish, synthesize:

```
HIG: <pass | N issues>
A11Y: <pass | N issues>

CRITICAL (must fix before commit):
- ...

NICE-TO-HAVE:
- ...
```

If both clean: `HIG + A11Y — clean. Safe to proceed.`
