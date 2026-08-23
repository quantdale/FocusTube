# Checkpoint — DV takeover: live-smoke dispatch blocked on gh auth (2026-08-23)

- Campaign: DEVICE_VALIDATION_V1 (unchanged)
- Packet: DV-A1-A14 (owner) / DV-8 diagnose-repair loop (agent)
- Starting HEAD = ending HEAD lineage: 51e1850 (docs-only tip over validated
  code baseline ab30b51; last production-code hardening commit remains 2c7646d)
- Worktree: clean before/after; main == origin/main (ff-only)

## What this session did

1. Synced from GitHub; verified no upstream advancement past 51e1850.
2. Fresh deterministic local baseline (Swift 6.3.3, Windows):
   `swift build` clean; `swift test` -> 74 XCTest + 11 swift-testing,
   0 failures.
3. Observed push-triggered CI on current HEAD 51e1850 via anonymous API:
   Core Tests run **32620238065** SUCCESS; iOS CI run **32620238054**
   SUCCESS. Code lineage green end-to-end.
4. Re-inspected the four opt-in smokes (LiveExtractionSmoke,
   PlaybackStartSmoke, AdaptiveLiveSmoke, DownloadLiveSmoke): all gated by
   `XCTSkipIf(FOCUSTUBE_LIVE_SMOKE != "1")`; ordinary push/PR runs remain
   deterministic. ios-ci.yml wires only the workflow_dispatch input to that
   env var.
5. Attempted the live-smoke gate prerequisite:
   - `gh auth status` -> NOT logged into any GitHub host;
   - GH_TOKEN / GITHUB_TOKEN unset in the authoring environment;
   - anonymous api.github.com cannot POST workflow_dispatch events
     (dispatch history total_count=0, re-checked 2026-08-23).

## Blocker (exact)

The one remaining agent-accessible validation — the opt-in live smoke —
requires an authenticated `gh` CLI (or a manual Actions-page dispatch).
This is an owner credential action; it cannot be synthesized, mocked, or
worked around without violating the no-fabricated-evidence rule.

Owner commands once authenticated:

    gh auth login
    gh workflow run ios-ci.yml --ref main -f live_smoke=true

Equivalent manual path: GitHub Actions -> iOS CI -> Run workflow ->
live_smoke=true on main. The agent will then track the run to completion
(jobs/logs/artifacts) and classify any failure per DV-8 diagnosis order.

## Defects found

None. Baseline green locally and on Apple CI; no failure reports exist to
drive DV-8; HARDENING_BACKLOG remains empty. No code changes made — none
were evidence-justified.

## Next waypoint

Unchanged: DEVICE_VALIDATION_BATCH_A_PENDING, now with two precise owner
inputs outstanding:
1. authenticated live-smoke dispatch (above), and
2. Part 0 setup + physical iPhone Batch A A1–A14 execution/evidence.

On either arriving: process evidence immediately (DV-8 repair loop for any
failure; DV-9 final report on full pass; DV-EXIT -> personal_release_validated).
