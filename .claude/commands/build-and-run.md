---
description: Build Cantio, kill any running instance, launch fresh.
---

!`xcodebuild -project Cantio.xcodeproj -scheme Cantio -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`

If the build above succeeded (`** BUILD SUCCEEDED **`), run:

!`killall Cantio 2>/dev/null; sleep 1; open /Users/mayron/projects/mayron/floric/.build/Build/Products/Debug/Cantio.app`

Then confirm: `Cantio launched.` Otherwise stop and report the build error.
