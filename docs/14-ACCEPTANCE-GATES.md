# 14 — Milestone Acceptance Gates

A milestone is complete only when its gate is evidenced.

## G0 — Bootstrap

- [ ] `swift test` passes for FocusTubeCore.
- [ ] XcodeGen generates project on macOS CI.
- [ ] iOS app target builds on accepted Xcode 26.x.
- [ ] available iPhone Simulator boots.
- [ ] app launches without crash.
- [ ] XCUITest verifies Home/Search/Downloads/Library tabs.
- [ ] CI records Xcode/Swift/XcodeGen/runtime versions.

## G1 — Media viability

- [ ] real long-form video resolves through YouTubeKit `.local`.
- [ ] normalized stream model never exposes >1080p.
- [ ] online playback succeeds in AVPlayer.
- [ ] one combined allowed-quality stream downloads and validates.
- [ ] downloaded file plays with network-disabled fixture/offline path.
- [ ] adaptive 1080p proof succeeds on a suitable sample or evidence proves native-mux limitation and triggers ADR review.
- [ ] no yt-dlp/remote fallback exists.

## G2 — Durable downloads

- [ ] explicit state-machine transition tests pass.
- [ ] app relaunch reconciles active background tasks.
- [ ] transient retry works.
- [ ] expired stream re-resolution works.
- [ ] insufficient-storage refusal works.
- [ ] cancellation leaves no final-file corruption.

## G3 — Account/API

- [ ] Google sign-in works in development environment.
- [ ] fake auth supports deterministic tests.
- [ ] subscription list loads.
- [ ] token/credential logging audit passes.
- [ ] quota errors are typed.

## G4 — Home/Focus

- [ ] feed derives from subscriptions.
- [ ] <=180s entries are filtered before rendering.
- [ ] `/shorts/` deep links are blocked.
- [ ] no Shorts shelf/tab/vertical swipe exists.
- [ ] paging is explicit, not infinite.

## G5 — Search

- [ ] remote search runs only on explicit submit.
- [ ] results are hydrated and short-filtered.
- [ ] quota exhaustion has useful UX.

## G6 — Video/comments/actions

- [ ] comments read works.
- [ ] comments-disabled state works.
- [ ] top-level comment and reply work with auth.
- [ ] subscribe/unsubscribe works if enabled.
- [ ] download picker contains only available subset of 1080/720/480/360.

## G7 — Library

- [ ] progress persists/reloads.
- [ ] offline media indexes reconcile with files.
- [ ] delete cleans file + metadata safely.
- [ ] history remains useful offline.

## G8 — Background media

- [ ] PiP verified.
- [ ] background audio verified.
- [ ] lock-screen metadata/commands verified.
- [ ] interruption recovery verified.
- [ ] designated physical-device checks recorded.

## G9 — Hardening

- [ ] deterministic full suite passes.
- [ ] live media smoke state understood.
- [ ] accessibility identifiers/audit complete.
- [ ] Critical/High defect count = 0.
- [ ] security/log audit passes.
- [ ] fresh agent can resume using repo state only.

## G10 — Personal release

- [ ] app installs on target iPhone.
- [ ] real extraction/playback works on device.
- [ ] 1080/720/480/360 picker behavior verified with representative videos.
- [ ] download/offline playback works on device.
- [ ] background/PiP/lock-screen behavior verified.
- [ ] known limitations documented.
