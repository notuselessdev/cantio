---
description: Spawn hig-reviewer + a11y-auditor in parallel on the current diff.
---

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
