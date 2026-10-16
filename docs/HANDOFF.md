# FocusTube handoff (on hold since 2026-10-17 00:27 Asia/Manila)

Development is paused at Michael's request. No merges since `89ac5c8` (#21).

## Open PRs (left as-is)
- **#22** `feat/app-switch-local-first`: app switch to local-first (ADR-0008); removes GoogleSignIn/Data API wiring; Home/Add/Library tabs. Core CI green. iOS UI test `testAddChannelLinkSubscribesLocally` failed because the keyboard stayed up over the tab bar after submit; fix `630f2c7` (AddView clears focus, scroll dismisses keyboard; test asserts keyboard gone). iOS CI on 630f2c7 was still running at pause. Merge only if all checks are green.
- **#23**: core cleanup of the leftover Data API/comments/ratings/download types. Stacked on #22: after #22 merges, retarget it with `gh api -X PATCH repos/quantdale/FocusTube/pulls/23 -f base=main`, run `git rebase --onto main <old #22 head>`, then merge on green.
- **#24** `docs/local-first-readme`: README rewrite for local-first, root-cause corrections in PROGRESS/VERIFICATION/ROADMAP, no-Codex rule in AGENTS.md/DECISIONS.md, and this handoff. Update its branch and merge on green.

## Next steps after restart
1. Land #22, then #23, then #24 (in that order, all green).
2. Update the pending lines in PROGRESS/VERIFICATION after they merge.
3. A one-time data cleanup PR for the leftover download records and files.
4. Remove the background-audio and remote-control code.
5. Phase 4: device validation on a real iPhone.

## Open blockers (owner-only)
- Mac + Xcode + signing (`DEVELOPMENT_TEAM` in Secrets.local.xcconfig).
- Device test batch on a real iPhone (IFrame player, PiP/lock-screen behaviour, RSS/oEmbed live fetches).
- M6: Michael confirms he accepts the losses from ADR-0007/0008 (no downloads, no background audio, no YouTube search, no @handle resolution).

## Rules
No Google Cloud / Data API / OAuth. No Codex PR reviews. Merge only on all-green CI. No paid services.
