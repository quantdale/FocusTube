# DECISIONS — Phase 1 Assessment

## Locked decisions found (source: README, START_HERE, docs/adr/0001–0006)
- Native SwiftUI, iOS 17+, Swift 6; no WebView (ADR-0001).
- YouTubeKit is the only extractor, local only; no yt-dlp or remote extractor (ADR-0002).
- XcodeGen generates the project; `.xcodeproj` is not committed (ADR-0003).
- The download ladder is exactly 1080/720/480/360; no transcoding to fill gaps (ADR-0004).
- No backend in V1 (ADR-0005).
- Per-quality media layout `Media/<id>/<quality>/` (ADR-0006).
- Runtime dependencies are limited to YouTubeKit and GoogleSignIn.
- Shorts are hard-blocked, with a conservative 180 s cutoff.

## Decisions made in this assessment
- D1: The assessment is docs only, on local branch `docs/phase1-assessment`.
  No push, no PR, no code changes.
- D2: The CI failure is classified as a test-determinism defect (P0), not a
  product regression. Basis: the hydration result is index-keyed
  (`YouTubeAPI.swift`), and the test asserts the order of recorded requests.
- D3: I did not reopen any locked decision. None of the evidence gathered
  requires an ADR.
- D4: "Feature-complete" is defined as spec jobs on device + green and
  non-flaky CI (see ROADMAP.md), not just CI green.

## 2026-10-16 — CI actions moved to Node 24 majors
Moved `actions/checkout` from v4 to v7, `actions/cache` from v4 to v6, and `actions/upload-artifact`
from v4 to v7. The v4 majors target Node 20, which is deprecated, and the runner forces them onto Node 24.
None of the inputs we use changed. The `aws/tap` untrusted-tap warning did not appear
in the 2026-10-15 iOS CI run (38761375821), so this change makes no Homebrew change.
