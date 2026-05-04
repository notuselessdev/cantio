---
description: Conventional commit for Cantio. Verifies tests green within last 5 min.
argument-hint: "<commit subject>"
---

Pre-flight:

!`git status --porcelain`
!`git diff --stat`
!`git log -5 --oneline`

Steps:

1. If staging area empty: stage relevant `Cantio/` and `CantioTests/` files (be explicit, never `git add .`). Skip secrets, asset binaries unless intended.
2. Verify last `xcodebuild test` was green:
   ```
   ls -t .build/Logs/Test/*.xcresult 2>/dev/null | head -1
   ```
   If older than 5 minutes or absent: run `/test-cantio` first; abort commit on failure.
3. Compose conventional commit. Subject: `<type>(<scope>): <summary>`. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. Scope examples: `pill`, `menu`, `prefs`, `lyrics`, `spotify`, `tests`.
4. Body: WHY, not WHAT. Two-three sentences max.
5. Commit via HEREDOC:
   ```
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <subject from $ARGUMENTS>

   <body>

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
6. Show `git status` after.

Never push. Never amend. Never `--no-verify`.
