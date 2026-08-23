# FINAL COMPLETION CAMPAIGN — FINAL_COMPLETION_V1

- Date: 2026-08-23
- Session type: comprehensive ship-readiness campaign (final engineering pass before physical-device validation)
- Starting SHA: `c0bd54b` (main, synced with origin)
- Final code SHA: `42f761a` (main, pushed)
- Docs/state reconciliation commit: this commit (docs-only)

## Why this campaign ran

The durable state claimed DEVICE_VALIDATION_V1 was waiting only on the owner,
but the anonymous GitHub API showed **iOS CI had been failing on every push
since the fixture-journey expansion landed** (`6ba1343`..`c0bd54b`, runs
#113–#115): unit tests passed while three XCUITest journeys failed at the
gate (`ui=65`). The recorded "CI green" claims described an older lineage.
This campaign diagnosed and fixed the real defects underneath, then restored
a fully green matrix.

## Defects found and fixed

### High — video page unreachable on the release OS (product)
Modal `.sheet` presentation of AVKit-hosting content never exposed its content
to the accessibility hierarchy on current iOS 26 runtimes (and blanked the
presenting context). Every video-page journey failed; the one Library journey
that "passed" did so vacuously by matching the tapped row's own label.
**Fix:** video page is now a **pushed `navigationDestination(item:)` route**
on all three hosts (Home, Search, Library) with an explicit Close action —
better navigation semantics and fully exposed to a11y/XCUITest.
Commits: `f7f6e8e`.

### High — LibraryStore was not observable (product)
`LibraryStore` is not `@Observable` and exposes computed SwiftData fetches, so
no SwiftUI view ever invalidated on mid-session mutations: a finished download
never appeared while the Downloads tab was frontmost, saves/deletes elsewhere
stale-rendered, etc. **Fix:** `@Observable` with an explicit revision counter
bumped by every mutation and read by every collection getter. Commit: `5c1d297`.

### Medium — player overlay states inflated their container row (product)
The loading/failed overlays used flexible max-dimension frames inside the List
row plus a stray `.ignoresSafeArea`; on failure (fixture URLs legitimately fail
to play) the player region grew toward viewport height and pushed every later
section below the fold. **Fix:** hard internal `.frame(height: 240)` bound;
removed `.ignoresSafeArea`. Commit: `1105e8d`.

### Medium — fixture download admission depended on host disk (test harness)
`VolumeStorage` refuses conservatively with 0 when the volume query fails or
free space is short; scripted fixture transfers were therefore refused on CI
simulators and never registered. **Fix:** `FixtureStorage` (fixed 512 GB)
injected through `AppDependencies`' storage seam for DEBUG fixture launches
only; production keeps `VolumeStorage`. Commit: `7b9bdd5`.

### Medium — Home pull-to-refresh missing vs docs/07
Added `.refreshable { await store.load() }` — an explicit user action, so the
full page-one reload is quota-appropriate. Commit: `f4105f6`.

### Product structure — video page List → ScrollView (commit `556d11b`)
List laziness intermittently omitted below-the-fold controls (Save/download
quality/comments) from the accessibility hierarchy entirely on this runtime.
A bounded detail page gains nothing from lazy rows; converted to
`ScrollView`+`VStack` so every element always exists for users, VoiceOver, and
XCUITest.

### Test infrastructure (iOS 26 XCUITest hazard set, commits `17fa015`,
`5aff70f`, `335a407`, `631aba9`, `ec5898f`, `565eac5`, `880ceee`, `7991a00`,
`8004529`, `14a2235`, `0585a38`, `42f761a`)
Documented and engineered around: lazy row materialization (elements do not
exist until scrolled near), unreliable `isHittable`, invalid activation points
near viewport edges, stale cached frames of captured elements (both geometry
and labels), mid-animation coordinate drift, alert message copy outside the
alert's staticTexts subtree, button-label child merging, degenerate
`app.frame`. Net result: `interact()` helper (geometry-driven reveal with
margin + time-separated frame-stability + native tap + enabled-gate), honest
Library assertion, typed-failure copy pinned at unit level
(`DownloadServiceTests.testTransportFailureCopyExplainsCauseAndRetry`),
happy-path alert probe in the downloads journey.

## Validation evidence (final HEAD `42f761a`)

- Core Tests (macOS runner): run **32666070090 SUCCESS**
- iOS CI (Debug build, Release build, unit tests, UI journeys, Gate):
  run **32666070146 SUCCESS**
  - Unit tests: 94 executed / 0 failures / 4 skipped (live smokes opt-in)
  - UI tests: all Journeys + LaunchTests green
- Windows local baseline: `swift build` clean; `swift test` 74/74, 0 failures
  (Swift 6.x toolchain).

## Static/policy audit (re-run this session)

- Shorts firewall: centralized `ShortFormPolicy` (+ `/shorts/` path block),
  applied pre-render in aggregator/search; UI journey asserts a seeded short
  never renders. No Shorts tab/shelf/route/swipe anywhere.
- yt-dlp / FFmpeg / remote extractor: absent (only comments asserting their
  absence). YouTubeKit `.local` only, behind `MediaExtracting`.
- Quality ladder: `allowedResolutions = {1080, 720, 480, 360}` enforced in
  Core; planner never downgrades or fabricates; 1080p ceiling tested.
- Secrets: repo-wide credential-pattern grep clean; only
  `Config/Secrets.local.xcconfig.example` tracked; real file gitignored;
  tokens logged nowhere (`privacy: .private` on error text).
- Generated project/artifacts not tracked; live smokes strictly opt-in.

## Residual audit results

- TODO/FIXME/HACK/fatalError scan: only intentional strict-test-fake
  `fatalError("unexpected call")` and the documented in-memory-container last
  resort.
- Dead code/duplication: bounded pass found nothing safely removable without
  destabilizing working architecture.
- Backlog additions: HB-013 (DownloadsView per-render record fetches, Low),
  HB-014 (fixture playback-failure overlay is expected behavior, Low).

## Remaining work — external only

Unchanged from DEVICE_VALIDATION_V1: owner Part 0 setup + Batch A items
A1–A14 on the physical iPhone, and exactly one opt-in live-smoke dispatch
(`gh workflow run ios-ci.yml --ref main -f live_smoke=true`) — gh remains
unauthenticated on the authoring host; anonymous dispatch is impossible.
