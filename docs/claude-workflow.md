# Claude Code Workflow — Cantio

Distilled from Boris Cherny (Claude Code creator) + applied to this Swift /
macOS / Apple-HIG project. The big idea: **vanilla Claude Code + tight
verification loop + workflows-as-slash-commands**.

---

## 1. The single most important rule

> "Give Claude a way to verify its work. If Claude has that feedback loop, it
> will 2-3× the quality of the final result." — Boris

For Cantio, verification = **`xcodebuild` + tests + (where possible) snapshot
diff or app-launch sanity check**. Every agent and every workflow ends with a
verify step. No "I think it works" without proof.

---

## 2. Default working mode

- **Start every non-trivial change in Plan mode** (`Shift+Tab` twice).
- Iterate on the plan with the lead until tight.
- Switch to auto-accept edits.
- Lead 1-shots the implementation with a good plan.
- For risky areas (Spotify integration, NSWindow lifecycle) — keep plan-gating
  on the spawned teammate (see `docs/agent-teams.md`).

## 3. Parallelism by default

Boris runs **5 Claudes in terminal + 5–10 on claude.ai/code**. Cantio is
smaller, so:

- **Local terminal lead (this session)** — orchestrator, code edits, builds.
- **Spawn 1–3 subagents** for: build verification, HIG review, test author.
- **Spawn full team (3–5 teammates)** only for cross-cutting work
  (visual refactor, multi-file feature, debug investigation).

Don't over-parallelize routine bug fixes — coordination overhead exceeds
benefit (see `docs/agent-teams.md`).

## 4. Model choice

Boris: "Opus 4.5 with thinking for everything. Even though it's bigger &
slower than Sonnet, you have to steer it less and it's better at tool use, so
it's almost always faster than using a smaller model in the end."

For Cantio:
- **Lead session:** Opus (Cantio is small, edits matter, taste matters).
- **Subagents that build/verify:** Haiku (mechanical, no judgment).
- **Subagents that review (HIG, a11y, code review):** Opus (judgment-heavy).
- **Subagents that write tests:** Sonnet (volume + correctness, less taste).

## 5. CLAUDE.md = team memory

> "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md."

Cantio's `CLAUDE.md` (project root) should contain:
- Build commands (`xcodebuild ...`).
- "Always test pill+minimal+fullscreen × glass+solid × light+dark before
  declaring UI work done."
- "Never use custom blur — always `NSVisualEffectView`."
- "Window must be `isOpaque = false` for material to show."
- "Settings opens via `SettingsLink`; remember to flip activation policy."
- Spotify scripting bridge quirks.
- Hot-key Carbon API quirks.
- Anti-patterns we've burned ourselves on (e.g. opaque pill bg seam, shadow
  bleeding upward).

Update CLAUDE.md anytime Claude makes a wrong assumption that should have been
prevented.

## 6. Slash commands for inner-loop workflows

Anything done > 2× per session → slash command in `.claude/commands/`.

Boris's example: `/commit-push-pr` with inline bash that pre-computes
`git status`, branch name, etc. — saves a roundtrip.

Cantio slash commands to write (see `.claude/commands/` once defined):

| Command            | Does                                                        |
| ------------------ | ----------------------------------------------------------- |
| `/build-and-run`   | xcodebuild → killall Cantio → open .app                     |
| `/test-cantio`     | xcodebuild test, terse output                               |
| `/snapshot-record` | re-record snapshot tests, show diff                         |
| `/hig-check`       | spawn `hig-reviewer` on uncommitted diff                    |
| `/gap-audit`       | spawn `regression-auditor` to find untested code            |
| `/commit-cantio`   | conventional commit, includes test status check             |
| `/spotify-permission-reset` | reset TCC for Cantio's Spotify automation perm     |

Use inline `!` bash inside command bodies for pre-computed context.

## 7. Subagents for repeated workflows

Boris uses `code-simplifier` (post-work cleanup) and `verify-app` (E2E test).
Cantio mirrors this — see `.claude/agents/`:

- `swift-builder` — verify build (replaces `verify-app` for this domain).
- `code-simplifier` — post-work cleanup (already a global skill — invoke).
- `hig-reviewer` — Apple HIG check.
- `a11y-auditor` — Reduce Motion / Reduce Transparency / VoiceOver check.
- `test-author` — write XCTest for changed code paths.
- `regression-auditor` — find untested code, drift detection.

## 8. Hooks for "last 10%"

Boris: "PostToolUse hook to format Claude's code... avoid formatting errors
in CI later."

Cantio hooks (write to `.claude/settings.json`):

- **PostToolUse on `Edit`/`Write` for `*.swift`**:
  Run `swift-format` (if installed) or `swiftformat` to keep style consistent.
- **PostToolUse on `Edit`/`Write` for `*.swift`**:
  Optionally trigger background `swift-builder` agent — only when file
  count > 1 to avoid noise.
- **Stop hook**:
  If uncommitted Swift changes exist + last `xcodebuild test` was failing or
  > 5 min old → remind to run tests before ending session.
- **PreToolUse on Bash `git commit`**:
  Block if `xcodebuild` shows uncompiled changes.

## 9. Permissions — pre-allow, don't skip

Boris: "I don't use `--dangerously-skip-permissions`. Instead, I use
`/permissions` to pre-allow common bash commands."

Cantio `.claude/settings.json` should pre-allow:

```json
{
  "permissions": {
    "allow": [
      "Bash(xcodebuild:*)",
      "Bash(killall Cantio)",
      "Bash(open /Users/mayron/Library/Developer/Xcode/DerivedData/**)",
      "Bash(swift-format:*)",
      "Bash(swiftformat:*)",
      "Bash(xcrun simctl:*)",
      "Bash(plutil:*)"
    ]
  }
}
```

## 10. Long-running tasks — Stop hook for verification

Boris: For long tasks, use a Stop hook to deterministically verify, OR the
`ralph-wiggum` plugin pattern.

For Cantio: `Stop` hook spawns `swift-builder` + runs snapshot tests if any
`*.swift` changed in this session. Catches "Claude said it's done but didn't
verify."

## 11. Use all tools

Boris uses Slack MCP, BigQuery, Sentry, Chrome extension. For Cantio:

- **GitHub MCP** (if installed) — PR review, issue lookup.
- **iTerm `it2` CLI** — for tmux split-pane teammates (already installed?).
- **Chrome MCP / Chrome extension** — N/A (Cantio is native macOS, not web).
- **Sentry** — N/A (no telemetry by design).

## 12. Capture wrong assumptions back into CLAUDE.md

After every PR / session: ask "what did Claude get wrong that the docs should
have prevented?" Add the anti-pattern to CLAUDE.md or to the relevant
`.claude/agents/` definition.

This is how the project's agent layer compounds in quality over time.

---

## Quick start each session

1. Read `CLAUDE.md`.
2. If task is non-trivial: enter Plan mode (`Shift+Tab` ×2).
3. Discuss plan with lead until tight.
4. Auto-accept; let lead implement.
5. Spawn `swift-builder` to verify.
6. If UI changed: spawn `hig-reviewer` + `a11y-auditor` in parallel.
7. If logic changed: spawn `test-author` to extend tests.
8. Run `/test-cantio`.
9. If green + reviews clean: `/commit-cantio`.
10. End-of-session: log any anti-patterns into CLAUDE.md.
