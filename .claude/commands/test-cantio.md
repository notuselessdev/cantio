---
description: Run CantioTests via xcodebuild test. Terse output.
---

!`xcodebuild -project Cantio.xcodeproj -scheme Cantio -configuration Debug test 2>&1 | tail -25`

Summarize:
- If `** TEST SUCCEEDED **`: `TESTS PASS — N executed`.
- If failed: list each failing test name + assertion message + file:line. Nothing else.
