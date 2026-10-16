# ADR-0007 — Official YouTube IFrame Player replaces stream extraction

**Status:** Accepted (2026-10-16). Supersedes ADR-0002 (YouTubeKit local extraction),
ADR-0004 (download quality ladder) and ADR-0006 (per-quality media layout).

## Context
FocusTube plays and downloads videos by extracting raw stream URLs with YouTubeKit 0.4.8
and handing them to AVPlayer / URLSession. That violates the YouTube API Services Terms
and Developer Policies (no separating, downloading or caching audiovisual content outside
the official player) and puts App Store review at risk (guideline 5.2.3: no saving or
downloading third-party media without authorization). Michael's hard limit: respect the
YouTube ToS and App Store guidelines; prefer the official Data API and the IFrame player.

## Decision
1. **Playback** uses the official YouTube IFrame Player API, embedded in a `WKWebView`
   (privacy-enhanced `youtube-nocookie.com` host, `playsinline=1`, `enablejsapi=1`,
   `origin` set). Configuration: `allowsInlineMediaPlayback = true`,
   `mediaTypesRequiringUserActionForPlayback = []`. The player UI and branding are not
   hidden or overlaid in a way that breaks the IFrame policy.
2. **Boundary.** Core (`FocusTubeCore`, Linux-testable) owns a `PlayerEngine` protocol,
   `IFramePlayerCommand` (JS rendering), `IFrameBridgeMessage` (JS→Swift parsing),
   `IFramePlayerController` (state machine) and `IFrameEmbedPage` (HTML). Only the iOS
   target imports WebKit (`WKWebViewPlayerEngine`, a thin adapter that evaluates commands
   and forwards `WKScriptMessage` bodies to the parser).
3. **Offline downloads are removed.** There is no compliant way to download YouTube
   media in a third-party app. During the migration the download UI and entry points are
   compiled out behind the Swift flag `FOCUSTUBE_LEGACY_DOWNLOADS`, which is **off by
   default and never set for any shipped/App Store configuration**. The flag exists only so
   the removal can land in small, CI-verified PRs; the code is deleted in phase 3 and the
   flag goes with it. Rationale for flag-then-delete over one big delete: the download
   stack spans ~10 app files, SwiftData records and ~10 test files; a single deletion PR
   cannot be verified on Linux and would be one large risky iOS-CI iteration.
4. **YouTubeKit is removed** from `project.yml` once no target references it (phase 3).
   No other extractor (yt-dlp, remote fallback, Invidious/Piped) replaces it.
5. Metadata, search, subscriptions, playlists and comments keep using the official
   YouTube Data API v3 (unchanged).

## Consequences
- **Picture in Picture:** AVPlayer-based PiP (`AVPictureInPictureController`) goes away.
  WKWebView inline video may offer system PiP on iOS 17+ only if WebKit exposes it for the
  embedded `<video>`; this is not guaranteed for the cross-origin YouTube iframe.
  Treat PiP as **unsupported** until proven on a device; device check A12 changes from
  "must work" to "record behavior".
- **Background audio:** The IFrame player pauses when the app backgrounds; keeping it
  playing would mean working around the player, which the policy disallows. Background
  audio is **dropped**. `BackgroundMediaPolicy`/`BackgroundMediaCoordinator` audio-session
  handling is reduced to foreground playback (`.playback` category is no longer needed for
  background continuation). A10 is rewritten.
- **Lock screen / Control Center:** our `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`
  wiring drove AVPlayer. WebKit may publish its own Now Playing info for web media; we do
  not fight it. Our remote-command targets are removed with AVPlayer; A11/A13 become
  "record behavior".
- **Downloads tab:** removed from the tab bar (compiled out by the flag, then deleted).
  The Library keeps History/Watch Later/Playlists. Existing on-device downloaded files
  from older builds are deleted on first launch of the migrated build (phase 3, one-time
  cleanup), and the quality picker goes away.
- **Quality selection:** controlled by the IFrame player itself; no custom picker.
- **Shorts focus policy** keeps working: it is enforced on Data API results before a
  video ever reaches the player.
- **Testing:** core state machine is unit-tested on Linux. Anything WebKit-related
  (page load, JS bridge round-trip, inline playback, autoplay) is **unverified** until
  macOS CI builds it and a device runs it.

## Migration plan
| Phase | Scope | Verified by |
|-------|-------|-------------|
| 1a | This ADR + doc updates (ROADMAP P-C, PROGRESS, VERIFICATION, BLOCKERS, checklist) | review |
| 1b | Core: `PlayerEngine`, IFrame command/bridge/controller/embed page + tests | Linux `swift test`, Core CI |
| 2 | iOS: `WKWebViewPlayerEngine` + SwiftUI host; `PlayerCoordinator`/`PlayerView`/`VideoPageView` switch to `PlayerEngine`; Downloads tab + quality picker behind `FOCUSTUBE_LEGACY_DOWNLOADS` (off); UI-test fixtures use a fake engine | macOS iOS CI (build + unit + UI journeys) |
| 3 | Delete `YouTubeKitMediaExtractor`, download stack, extraction core (`MediaExtracting`, `AdaptiveSelection`, `MediaStreamFilter`, `DownloadPlanner`…), live-smoke extraction tests, the flag, and YouTubeKit from `project.yml`; one-time cleanup of old download files; remove background-audio/remote-command code | macOS iOS CI |
| 4 | Device validation of the new player (inline play, errors 101/150 surfaced, rotation/fullscreen, PiP/lock-screen behavior recorded) | owner device |
