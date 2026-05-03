#!/bin/bash
# End-of-session reminder: if Swift was edited and tests not run recently, nudge.

set +e

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0

# Any uncommitted Swift changes?
swift_changes=$(git status --porcelain 2>/dev/null | grep -E '\.swift$' | head -1)
if [ -z "$swift_changes" ]; then
  exit 0
fi

# Most recent test result.
latest=$(ls -t /Users/mayron/Library/Developer/Xcode/DerivedData/Floric-*/Logs/Test/*.xcresult 2>/dev/null | head -1)
if [ -z "$latest" ]; then
  echo "REMINDER: Swift edits uncommitted; no test runs found. Consider /test-floric."
  exit 0
fi

age_sec=$(( $(date +%s) - $(stat -f %m "$latest" 2>/dev/null || echo 0) ))
if [ "$age_sec" -gt 300 ]; then
  age_min=$(( age_sec / 60 ))
  echo "REMINDER: Swift edits uncommitted; last test was ${age_min}m ago. Consider /test-floric."
fi

exit 0
