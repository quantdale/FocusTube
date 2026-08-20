# START HERE — FocusTube Agent Entry Point

This repository is designed so a fresh coding agent can recover the project state without relying on chat history.

## 1. Mission

Build FocusTube: a personal native iOS YouTube client for intentional long-form viewing, with native playback and offline downloads, while eliminating Shorts and short-form consumption mechanics.

The first engineering objective is **not UI completeness**. The first objective is to prove the riskiest technical path end-to-end:

```text
YouTube video ID
  -> YouTubeKit local extraction
  -> allowed stream selection (1080/720/480/360 only)
  -> AVPlayer playback
  -> background download
  -> adaptive audio/video mux when necessary
  -> validated local file
  -> offline AVPlayer playback
```

Until that path is proven on the iOS Simulator and later on a physical iPhone, the project is not allowed to spend significant effort on polish.

## 2. Required reading order

Before editing code, read these files in order:

1. `AGENTS.md`
2. `.agent/STATE.yaml`
3. `.agent/GOAL.md`
4. `.agent/OPERATING_CONTRACT.md`
5. `.agent/STATE_MACHINE.md`
6. `docs/00-PRODUCT-SPEC.md`
7. `docs/01-ARCHITECTURE.md`
8. `docs/02-MEDIA-EXTRACTION-PLAYBACK.md`
9. `docs/03-DOWNLOAD-SYSTEM.md`
10. `docs/08-WINDOWS-REMOTE-IOS-DEVELOPMENT.md`
11. `docs/09-TESTING-QA.md`
12. `docs/13-ROADMAP.md`
13. `docs/14-ACCEPTANCE-GATES.md`
14. Current work packet under `.agent/work-packets/`.

Do not infer requirements from memory when the repository contains a specification.

## 3. Locked decisions

These are not open design questions:

- Product name: **FocusTube**.
- Target: iPhone-first native iOS application.
- Minimum deployment target: iOS 17.0.
- SwiftUI + Swift 6 language mode.
- Playback: AVPlayer + AVPlayerViewController via a SwiftUI wrapper.
- Extraction: YouTubeKit only, local extraction only.
- No yt-dlp fallback.
- No remote extraction server.
- Download quality set: **1080p, 720p, 480p, 360p only**.
- Never expose 1440p/2160p even if YouTubeKit returns them.
- No custom transcoding merely to manufacture a missing resolution.
- Background downloads: Foundation URLSession background sessions.
- Adaptive muxing: native AVFoundation composition/export first; do not add FFmpeg without a new ADR.
- Metadata persistence: SwiftData.
- Media persistence: filesystem under Application Support.
- OAuth: GoogleSignIn.
- YouTube metadata/account API: direct typed URLSession client for YouTube Data API v3.
- No Alamofire, Firebase, Supabase, React Native, Expo, embedded YouTube WebView, or generic backend.
- Windows is the authoring/orchestration environment; macOS CI is the Apple build/test plane.
- XcodeGen owns project generation. Do not commit generated `.xcodeproj` state.
- Shorts are prohibited by product design; no vertical swipe player may be introduced.

If implementation evidence forces a locked decision to change, stop and create an ADR proposal instead of silently changing architecture.

## 4. Current waypoint

Read `.agent/STATE.yaml`. The current starting milestone is **M0 — Bootstrap and reproducible Apple CI**, followed by **M1 — Media viability proof**.

The first work packet is `.agent/work-packets/WP-000-BOOTSTRAP.md`.

## 5. Definition of an acceptable agent iteration

Every implementation iteration must:

1. identify the active work packet;
2. make the smallest coherent change that advances its acceptance criteria;
3. run every locally available deterministic test;
4. push through the repository's remote macOS CI when Apple-only verification is required;
5. inspect failures rather than merely retrying them;
6. update `.agent/STATE.yaml` with evidence and the next waypoint;
7. leave the repository buildable at checkpoint boundaries.

A statement like "should work" is not evidence. Accepted evidence is a command result, test result, simulator launch, screenshot, artifact, or physical-device validation record.

## 6. Initial commands on Windows

```powershell
swift --version
swift test
```

If Swift is not installed, follow `docs/08-WINDOWS-REMOTE-IOS-DEVELOPMENT.md`.

The Windows machine is not expected to build SwiftUI/AVKit. It tests `FocusTubeCore` and authors the repository. iOS-specific verification happens on macOS.
