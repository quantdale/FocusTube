# MAC FINALIZATION CHECKLIST

Prerequisite: B1 is fixed and CI is green on the new tip. Use that SHA, not
`7a70943`.

## Toolchain
- [ ] Xcode 26.x (26.6 preferred) with an iOS 17+ SDK; `xcode-select` points at it
- [ ] `brew install xcodegen` (>= 2.46.0)
- [ ] `swift test` passes on the Mac (repeat the flaky test about 20 times)
- [ ] `xcodegen generate` → open `FocusTube.xcodeproj`; packages resolve (GoogleSignIn 9.0.0; YouTubeKit removed per ADR-0007)
- [ ] Build Debug and Release for the Simulator; run FocusTubeTests and FocusTubeUITests (expect 20/20 journeys)

## Signing and secrets (never commit)
- [ ] Copy `Config/Secrets.local.xcconfig.example` to `Config/Secrets.local.xcconfig`
- [ ] Set `DEVELOPMENT_TEAM`; set `PRODUCT_BUNDLE_IDENTIFIER` only if `com.quantdale.FocusTube` conflicts
- [ ] In Google Cloud, create an iOS OAuth client for the bundle id and enable YouTube Data API v3
- [ ] Fill in `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID`; regenerate the project

## Device (DEVICE_VALIDATION_BATCH_A.md, A1–A14)
- [ ] Install on the iPhone and trust the developer certificate
- [ ] A1 launch → A2 sign in → A3 feed / Load more → A4–A5 search → A6 play
- [ ] ~~A7 quality picker, A8 background download, A9 offline playback~~ retired (ADR-0007); check relaunch resume of online playback instead
- [ ] A10 background audio / lock screen → A11 Control Center single action → A12 PiP → A13 headset → A14 delete and storage reclaimed
- [ ] Extra: phone-call interruption; Wi-Fi ↔ cellular during download and playback
- [ ] Record the iPhone model and iOS version; photos for A2/A6/A10/A12

## CI
- [ ] Dispatch `ios-ci.yml` with `live_smoke=true` once and record the run ID
- [ ] Update `.agent/STATE.yaml` with the evidence (owner or agent, after observing it)

## Compliance migration (ADR-0007) — after phase 2 merges
- [ ] Video plays inline in the embedded IFrame player (youtube-nocookie), no extraction
- [ ] Play/pause/seek from our controls reach the player; progress updates
- [ ] A video with embedding disabled shows the "can't play here" error (codes 101/150), with an "Open in YouTube" option
- [ ] Fullscreen and rotation work
- [ ] Record (don't require) PiP, lock-screen and background behavior; A8, A9, A14 (downloads) are retired
- [ ] Release build has no Downloads tab or quality picker (`FOCUSTUBE_LEGACY_DOWNLOADS` unset)
