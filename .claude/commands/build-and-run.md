---
description: Build Floric, kill any running instance, launch fresh.
---

!`xcodebuild -project Floric.xcodeproj -scheme Floric -configuration Debug build 2>&1 | tail -5`

If the build above succeeded (`** BUILD SUCCEEDED **`), run:

!`killall Floric 2>/dev/null; sleep 1; open /Users/mayron/Library/Developer/Xcode/DerivedData/Floric-fnwupgjjunpatsdxtznclmteokxi/Build/Products/Debug/Floric.app`

Then confirm: `Floric launched.` Otherwise stop and report the build error.
