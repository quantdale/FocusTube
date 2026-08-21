# 14 — Milestone Acceptance Gates

A gate is evidence, not intent. Check a criterion only after observing the required result.

During `IMPLEMENTATION_V1`, physical-device-only evidence is explicitly deferred unless a device is already available to the agent. The implementation campaign must not falsely claim device verification, but it also must not stall solely because the user is absent.

## G0 — Bootstrap

- [ ] `swift test` passes for FocusTubeCore in a supported local/CI environment.
- [ ] XcodeGen generates project on macOS CI.
- [ ] iOS app target builds on accepted Xcode 26.x.
- [ ] an available compatible iPhone Simulator boots.
- [ ] app installs/launches without crash.
- [ ] XCUITest verifies Home/Search/Downloads/Library root tabs.
- [ ] CI records Xcode/Swift/XcodeGen/runtime versions and retains useful result/log artifacts.

## G1 — Media viability

- [ ] real representative long-form video resolves through YouTubeKit `.local`.
- [ ] normalized stream model never exposes >1080p.
- [ ] allowed-quality policy is exactly 1080/720/480/360 and missing qualities are not fabricated.
- [ ] online playback succeeds in AVPlayer/AVPlayerViewController.
- [ ] one combined allowed-quality stream downloads and validates.
- [ ] finalized local file plays through the offline/local-media path.
- [ ] adaptive 1080p proof succeeds on a suitable sample, or observed native-mux incompatibility is documented and triggers ADR review rather than an unauthorized fallback.
- [ ] no yt-dlp/remote-extractor/FFmpeg convenience fallback exists.
- [ ] deterministic adapter/selection/error tests pass independently of live YouTube state.

## G2 — Durable downloads

- [ ] explicit download state-machine transition tests pass.
- [ ] app relaunch/reconstruction reconciles persisted state with active background tasks/files.
- [ ] transient retry policy works.
- [ ] expired/signed stream re-resolution path works.
- [ ] insufficient-storage refusal works before destructive partial work.
- [ ] cancellation/failure leaves no corrupt final media.
- [ ] orphan temp/final metadata reconciliation has deterministic coverage.

## G3 — Account/API

- [ ] fake auth supports deterministic authenticated-app tests.
- [ ] typed YouTube API client handles success/auth/quota/network/decode error classes.
- [ ] subscription-list integration is implemented and deterministically tested.
- [ ] safe real Google sign-in/subscription smoke is observed when development credentials are available; otherwise the missing external configuration is recorded without blocking unrelated implementation.
- [ ] token/credential/logging audit for touched paths passes.

## G4 — Home/Focus

- [ ] Home feed derives from subscriptions/uploads rather than an unbounded recommendation feed.
- [ ] duration is known before short-form eligibility decision.
- [ ] <=180-second entries are filtered before rendering.
- [ ] `/shorts/` deep links/routes are blocked.
- [ ] no Shorts tab/shelf/vertical swipe/autoplay-next path exists.
- [ ] paging is explicit user-triggered load-more, not infinite automatic fetch.
- [ ] deterministic no-Shorts regression tests cover boundary cases.

## G5 — Search

- [ ] remote search runs only on explicit submit.
- [ ] results hydrate duration/details before rendering eligibility.
- [ ] short-form results are filtered before render.
- [ ] pagination is intentional/quota-aware.
- [ ] quota exhaustion and API failure have typed/useful UX.

## G6 — Video/comments/actions

- [ ] production video-detail composition uses the native playback boundary.
- [ ] comments read/pagination works.
- [ ] comments-disabled state works.
- [ ] top-level comment and reply paths are implemented with deterministic authenticated tests and safe real integration when credentials permit.
- [ ] subscribe/unsubscribe works if included in V1 action surface.
- [ ] selected rating action works if included.
- [ ] download picker contains only the actually available subset of 1080/720/480/360.

## G7 — Library

- [ ] playback progress persists/reloads.
- [ ] local history/saves remain useful offline.
- [ ] offline-media index reconciles with filesystem reality.
- [ ] delete removes file + metadata safely without half-deleted final state.
- [ ] storage usage/UI updates after reconciliation/delete.
- [ ] migration/reconciliation behavior has deterministic coverage.

## G8 — Background media implementation

Automated implementation-complete criteria:

- [ ] required background/media project capabilities build correctly.
- [ ] AVAudioSession/background-audio integration is implemented.
- [ ] Now Playing metadata integration is implemented and testable coordinator logic passes.
- [ ] MPRemoteCommandCenter command handling is implemented with deterministic logic tests where practical.
- [ ] PiP integration is wired through the supported AVPlayer/AVPlayerViewController path.
- [ ] interruption/route-change state handling is implemented and unit/integration-tested where practical.
- [ ] simulator-supported smoke tests pass where meaningful.
- [ ] physical-device-only checks are explicitly listed as deferred rather than claimed.

Physical device checks for PiP/background suspension/lock screen/Bluetooth do **not** block `IMPLEMENTATION_V1`; they move to G10.

## IC-EXIT — Implementation campaign exit

All must hold:

- [ ] G0–G8 implementation criteria are satisfied, with explicitly allowed external/device evidence deferred and recorded.
- [ ] full deterministic test suite passes.
- [ ] current iOS app builds and launches on automated Apple build plane.
- [ ] main user flows have simulator smoke/UI coverage at least for navigation and deterministic fixture-backed behavior.
- [ ] no known Critical/High defect remains.
- [ ] no known secret leakage or destructive persistence issue remains.
- [ ] no Shorts surface/route/vertical swipe path exists.
- [ ] download ceiling remains 1080p and picker policy remains exact.
- [ ] `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, checkpoints, and hardening backlog reflect current reality.
- [ ] a fresh agent can identify what is complete and why without chat history.

On pass under INTEGRATION_COMPLETION_V1: record evidence, then continue directly into HARDENING_V1 (the owner has explicitly authorized the full completion campaign including hardening and personal release). The terminal state is `personal_release_candidate`, or `implementation_complete_external_validation_required` only if a genuine external blocker remains.

---

# Later campaign gates

## G9 — Hardening

- [ ] deterministic full suite passes after torture/hardening changes.
- [ ] live media smoke state is understood.
- [ ] low-storage/network-loss/process-termination/extraction-breakage scenarios are exercised.
- [ ] accessibility identifiers/audit complete.
- [ ] performance/memory audit complete for target flows.
- [ ] Critical/High defect count = 0.
- [ ] security/log-redaction audit passes.
- [ ] fresh-agent recovery exercise passes.

## G10 — Personal release / physical device

- [ ] app signs/installs on target iPhone.
- [ ] real extraction/playback works on device.
- [ ] representative 1080/720/480/360 picker behavior verified on device.
- [ ] download/offline playback works on device.
- [ ] PiP verified on device.
- [ ] background audio under real suspension/interruption verified.
- [ ] lock-screen/headset/Bluetooth command behavior verified as applicable.
- [ ] storage/delete/relaunch behavior spot-checked on device.
- [ ] known limitations/recovery steps documented.