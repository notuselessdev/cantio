---
description: Run FloricTests via xcodebuild test. Terse output.
---

!`xcodebuild -project Floric.xcodeproj -scheme Floric -configuration Debug test 2>&1 | tail -25`

Summarize:
- If `** TEST SUCCEEDED **`: `TESTS PASS — N executed`.
- If failed: list each failing test name + assertion message + file:line. Nothing else.
