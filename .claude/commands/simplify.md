---
description: Spawn code-simplifier on recent changes. Removes dead code, duplication, stale comments.
---

Spawn the `code-simplifier` subagent. Brief: "Scope: files changed in current `git diff HEAD`. Per your definition — remove only, never add. Stop on first build failure. Report removals."

After agent finishes, run:

!`xcodebuild -project Cantio.xcodeproj -scheme Cantio -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`

Confirm build still green. Run `/test-cantio` if any logic-bearing files changed.
