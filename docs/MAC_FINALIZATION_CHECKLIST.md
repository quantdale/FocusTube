# MAC FINALIZATION CHECKLIST

Prerequisite: B1 is fixed and CI is green on the new tip. Use that SHA, not
`7a70943`.

## Toolchain
- [ ] Xcode 26.x (26.6 preferred) with an iOS 17+ SDK; `xcode-select` points at it
- [ ] `brew install xcodegen` (>= 2.46.0)
- [ ] `swift test` passes on the Mac (repeat the flaky test about 20 times)
- [ ] `xcodegen generate` → open `FocusTube.xcodeproj`; packages resolve (no YouTubeKit or GoogleSignIn after ADR-0007/0008 land)
- [ ] Build Debug and Release for the Simulator; run FocusTubeTests and FocusTubeUITests (expect 20/20 journeys)

## Signing and secrets (never commit)
- [ ] Copy `Config/Secrets.local.xcconfig.example` to `Config/Secrets.local.xcconfig` and set only `DEVELOPMENT_TEAM` (no Google Cloud, OAuth client or API key; see ADR-0008)
- [ ] Set `PRODUCT_BUNDLE_IDENTIFIER` only if `com.quantdale.FocusTube` conflicts

## Device (DEVICE_VALIDATION_BATCH_A.md, A1–A14)
- [ ] Install on the iPhone and trust the developer certificate
- [ ] A1 launch → A2 paste a `/channel/UC…` link and subscribe → A3 subscriptions feed refreshes → A4 paste a video link and play → A5 paste a playlist link → A6 a pasted `/shorts/` link is rejected
- [ ] A7–A9 (downloads) retired by ADR-0007; check that resume after relaunch works for online playback
- [ ] A10 background audio / lock screen → A11 Control Center single action → A12 PiP → A13 headset (record behavior, ADR-0007); A14 retired
- [ ] Extra: phone-call interruption; Wi-Fi ↔ cellular during playback and feed refresh
- [ ] Record the iPhone model and iOS version; photos for A2/A6/A10/A12

## CI
- [ ] Update `.agent/STATE.yaml` with the evidence (owner or agent, after observing it)

## Compliance migration (ADR-0007) — after phase 2 merges
- [ ] Video plays inline in the embedded IFrame player (youtube-nocookie), no extraction
- [ ] Play/pause/seek from our controls reach the player; progress updates
- [ ] A video with embedding disabled shows the "can't play here" error (codes 101/150), with an "Open in YouTube" option
- [ ] Fullscreen and rotation work
- [ ] Record (don't require) PiP, lock-screen and background behavior; A8, A9, A14 (downloads) are retired
- [ ] Build has no Downloads tab or quality picker
