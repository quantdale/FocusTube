# Checkpoint — DEVICE_VALIDATION_V1 readiness re-audit (2026-08-23)

- Campaign: DEVICE_VALIDATION_V1 (unchanged; no gate crossed)
- Packet: DV-A1-A14 (owner) / DV-8 diagnose-repair loop (agent)
- State at open: `device_validation_in_progress`, waiting_on_owner
- Starting HEAD: 3a2936e (docs commit on top of validated baseline ab30b51)
- Ending HEAD: this checkpoint's docs commit (no code changes)
- Worktree: clean before and after; origin/main in sync (ff-only)

## Purpose

Fresh-session verification that the recorded waiting-on-owner state still
matches reality, per DEVICE_VALIDATION_V1 agent duties ("keep CI green, record
evidence"), before any owner work is requested. No feature, hardening, or
refactor work was performed.

## Baseline evidence observed 2026-08-23

- `git fetch --all --prune` + `git pull --ff-only origin main`: already up to
  date; HEAD = 3a2936e793708dc21088b1de4867deaedaa86729.
- Windows local deterministic baseline (Swift 6.3.3,
  x86_64-unknown-windows-msvc):
  - `swift build` clean.
  - `swift test` green: "Executed 74 tests, with 0 failures" (XCTest) plus
    swift-testing run "Test run with 11 tests in 0 suites passed".
- GitHub Actions via anonymous api.github.com:
  - HEAD 3a2936e (docs-only): Core Tests run **32619393566** SUCCESS;
    iOS CI run **32619393541** SUCCESS — job steps verified individually:
    Select Xcode / XcodeGen / Test FocusTubeCore / Generate project /
    Resolve packages / boot simulator / Build (Debug) / Unit tests /
    UI tests / Gate all success.
  - Baseline ab30b51 runs unchanged from STATE.yaml
    (Core 32607499216 / iOS CI 32607499244).
  - No red workflow anywhere on the recent push lineage (last red was iOS CI
    run 32583961990 on docs-only 747b9cb, superseded by fixed 2c7646d).
- Live-smoke dispatch history: GET
  `/actions/runs?event=workflow_dispatch` → `total_count=0`. The opt-in live
  smoke has never been dispatched; STATE.yaml's claim remains accurate.
- Authoring-host credentials: `gh auth status` → not logged into any GitHub
  host; GH_TOKEN/GITHUB_TOKEN unset. Anonymous API cannot POST a
  workflow_dispatch, so the live smoke remains an owner prerequisite.

## Release-validation readiness audit (all PASS, no code changes needed)

| Item | Verified state |
|---|---|
| Signing config | `DEVELOPMENT_TEAM` flows from `Config/Secrets.local.xcconfig` (`#include?` in Debug/Release.xcconfig) into automatic signing |
| Bundle identifier | `com.quantdale.FocusTube` in project.yml; overridable via `PRODUCT_BUNDLE_IDENTIFIER` xcconfig override |
| Secrets exclusion | `.gitignore` covers `Config/Secrets.local.xcconfig`; file ABSENT locally; example contains only empty values; nothing credential-shaped in tree |
| XcodeGen propagation | target `configFiles` Debug/Release wired to Config/*.xcconfig |
| GoogleSignIn URL config | Info.plist `GIDClientID` ← `GOOGLE_CLIENT_ID`; `CFBundleURLSchemes[0]` ← `GOOGLE_REVERSED_CLIENT_ID`; FocusTubeAppDelegate forwards URL to `GIDSignIn.sharedInstance.handle(url)` |
| Google OAuth client integration | `GoogleSignInAuthSession`: single-flight `configure()`, `signIn`, `restorePreviousSignIn`, `signOut` behind typed AuthSession boundary |
| YouTube Data API v3 | typed URLSession client on OAuth user tokens (no API key required); decode/quota/auth error classes tested |
| Background modes | Info.plist `UIBackgroundModes = [audio]` |
| PiP | `allowsPictureInPicturePlayback = true` on PlayerCoordinator's AVPlayerViewController (App/Playback/PlayerCoordinator.swift) |
| AVAudioSession | `.playback` category / `.moviePlayback` mode; interruption + route-change observers mapped through BackgroundMediaPolicy |
| Background URLSession identifier | stable `com.quantdale.FocusTube.background` (BackgroundDownloadTransport.sessionIdentifier); relaunch reattachment + completion handler boxing covered by tests |
| Media filesystem paths | Application Support/FocusTube/Media/<videoID>/<quality>/ per ADR-0006; reconcile/prune tests green |
| SwiftData persistence | AppDependencies owns ModelContainer with do/catch fallback ladder; LibraryStore reconcile/atomic-delete tests green |
| Shorts filtering | ShortFormPolicy (<=180s conservative boundary), route block, pre-render filtering — Core suite green today |
| Download quality restrictions | ladder locked to 1080/720/480/360; missing qualities not manufactured; >1080 never selected — green today |
| Live-smoke workflow wiring | ios-ci.yml `workflow_dispatch.inputs.live_smoke` → `FOCUSTUBE_LIVE_SMOKE` env on unit-test step → 4 opt-in smokes (LiveExtractionSmoke, PlaybackStartSmoke, AdaptiveLiveSmoke, DownloadLiveSmoke) |

## Defects found

None. No Critical/High or Medium/Low issue surfaced; HARDENING_BACKLOG stays
empty of open items. No device/live failure reports exist yet to drive DV-8.

## Owner prerequisites (unchanged, now re-verified as exact blockers)

1. Part 0 setup: Apple team signing, Google Cloud iOS OAuth client +
   YouTube Data API enablement, `Config/Secrets.local.xcconfig` values.
2. Physical iPhone execution of Batch A A1–A14 with per-item evidence.
3. One live-smoke dispatch: either `gh auth login` on the authoring host then
   `gh workflow run ios-ci.yml --ref main -f live_smoke=true`, or a manual
   Actions-page dispatch with live_smoke=true.

## Next waypoint

Unchanged: DEVICE_VALIDATION_BATCH_A_PENDING. On owner evidence return:
DV-8 diagnose→repair→re-CI loop for any failed item, then DV-9 final report;
on full pass, DV-EXIT → `personal_release_validated`.
